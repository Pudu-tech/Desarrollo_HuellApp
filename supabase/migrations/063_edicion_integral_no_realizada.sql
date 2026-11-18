-- ============================================================
-- HuellApp · Migración 063
-- Edición integral de instancias y corrección de NO_REALIZADA
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- - Permitir que UPDATE_ASSIGNMENT edite una instancia NO_REALIZADA
--   como corrección administrativa, sin reabrirla ni reenviar invitaciones.
-- - Permitir reemplazar el conjunto de participantes dentro de la misma
--   transacción que actualiza los demás datos de la instancia.
-- - Reutilizar el flujo vigente de reconfirmación para PENDIENTE/CONFIRMADA.
-- - Conservar CANCELADA como estado cerrado para edición normal.
-- - Mantener historial de participantes mediante soft-delete y auditoría.
--
-- SEGURIDAD
-- ------------------------------------------------------------
-- FastAPI valida alcance de Directiva/Coordinador y recursos seleccionados.
-- Esta RPC vuelve a exigir UPDATE_ASSIGNMENT y, cuando se modifican
-- participantes, REASSIGN_ASSIGNMENT. Solo service_role puede ejecutarla.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. El trigger de reconfirmación permite una corrección histórica
--    exclusivamente cuando la RPC marca huellapp.edicion_historica=true.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.renovar_invitaciones_asignacion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
    v_changed boolean;
    v_pending uuid;
    v_pending_assignment uuid;
    v_part record;
    v_new jsonb;
    v_role uuid;
    v_old_state text;
    v_new_state text;
BEGIN
    v_changed:= NEW.fecha IS DISTINCT FROM OLD.fecha OR NEW.hora_inicio IS DISTINCT FROM OLD.hora_inicio
      OR NEW.hora_fin IS DISTINCT FROM OLD.hora_fin OR NEW.colegio_id IS DISTINCT FROM OLD.colegio_id
      OR NEW.curso_colegio_id IS DISTINCT FROM OLD.curso_colegio_id OR NEW.sala_id IS DISTINCT FROM OLD.sala_id
      OR NEW.ramo_id IS DISTINCT FROM OLD.ramo_id OR NEW.espacio_reflexion_id IS DISTINCT FROM OLD.espacio_reflexion_id
      OR NEW.espacio_encuentro_id IS DISTINCT FROM OLD.espacio_encuentro_id OR NEW.lugar IS DISTINCT FROM OLD.lugar
      OR NEW.tipo_actividad_id IS DISTINCT FROM OLD.tipo_actividad_id;

    SELECT codigo INTO v_old_state FROM public.estados_asignacion WHERE id=OLD.estado_id;
    SELECT codigo INTO v_new_state FROM public.estados_asignacion WHERE id=NEW.estado_id;

    IF v_changed THEN
        -- Corrección administrativa: conserva NO_REALIZADA y no toca respuestas,
        -- versiones de invitación ni notificaciones.
        IF v_old_state='NO_REALIZADA'
           AND v_new_state='NO_REALIZADA'
           AND current_setting('huellapp.edicion_historica', true)='true' THEN
            RETURN NEW;
        END IF;

        IF NOT NEW.activo OR NEW.deleted_at IS NOT NULL
           OR v_old_state NOT IN ('PENDIENTE','CONFIRMADA')
           OR v_new_state NOT IN ('PENDIENTE','CONFIRMADA')
           OR (OLD.fecha+OLD.hora_fin) AT TIME ZONE 'America/Santiago'<=now()
           OR (NEW.fecha+NEW.hora_fin) AT TIME ZONE 'America/Santiago'<=now()
           OR EXISTS(
                SELECT 1
                FROM public.asistencias_asignacion s
                JOIN public.asignacion_participantes p ON p.id=s.asignacion_participante_id
                WHERE p.asignacion_id=NEW.id AND s.estado<>'PENDIENTE'
           ) THEN
            RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ASSIGNMENT_RECONFIRMATION_UNAVAILABLE';
        END IF;

        IF current_setting('huellapp.edicion_rpc',true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ASSIGNMENT_RECONFIRMATION_UNAVAILABLE';
        END IF;

        SELECT id INTO v_pending FROM public.estados_participacion WHERE codigo='PENDIENTE' AND activo;
        SELECT id INTO v_pending_assignment FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
        IF v_pending IS NULL OR v_pending_assignment IS NULL THEN
            RAISE EXCEPTION 'Faltan estados PENDIENTE activos';
        END IF;

        SELECT rol_id INTO v_role FROM public.usuarios WHERE id=NEW.updated_by;
        FOR v_part IN
            SELECT *
            FROM public.asignacion_participantes
            WHERE asignacion_id=NEW.id AND activo AND deleted_at IS NULL
            ORDER BY id
            FOR UPDATE
        LOOP
            UPDATE public.asignacion_participantes
            SET estado_participacion_id=v_pending,
                motivo_rechazo=NULL,
                fecha_respuesta=NULL,
                respondido_por=NULL,
                invitacion_version=gen_random_uuid(),
                updated_at=now(),
                updated_by=NEW.updated_by
            WHERE id=v_part.id
            RETURNING to_jsonb(asignacion_participantes) INTO v_new;

            UPDATE public.notificaciones
            SET titulo='Asignación actualizada en HuellApp',
                mensaje='Las condiciones de la actividad cambiaron. Confirma nuevamente tu participación.'
            WHERE participacion_id=v_part.id
              AND invitacion_version=(v_new->>'invitacion_version')::uuid;

            INSERT INTO public.audit_logs(
                actor_user_id,actor_role_id,action,entity_type,entity_id,
                old_values,new_values,description,request_id,ip_address,
                user_agent,source
            ) VALUES(
                NEW.updated_by,v_role,'REQUEST_PARTICIPATION_RECONFIRMATION',
                'ASSIGNMENT_PARTICIPANT',v_part.id,to_jsonb(v_part),v_new,
                'Reconfirmación por cambio de condiciones de la asignación.',
                nullif(current_setting('huellapp.request_id',true),'')::uuid,
                nullif(current_setting('huellapp.ip_address',true),'')::inet,
                nullif(current_setting('huellapp.user_agent',true),''),'WEB'
            );
        END LOOP;

        PERFORM set_config('huellapp.reconfirm_assignment',NEW.id::text,true);
    ELSIF (NEW.activo AND NOT OLD.activo)
       OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
       OR (NEW.estado_id IS DISTINCT FROM OLD.estado_id AND v_old_state NOT IN ('PENDIENTE','CONFIRMADA')) THEN
        -- Una corrección administrativa NO_REALIZADA -> NO_REALIZADA no entra aquí.
        UPDATE public.asignacion_participantes
        SET invitacion_version=gen_random_uuid()
        WHERE asignacion_id=NEW.id AND activo AND deleted_at IS NULL;
    END IF;

    RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 2. RPC transaccional de edición integral.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualizar_asignacion_completa_atomica(
    p_asignacion_id uuid,
    p_cambios jsonb,
    p_reemplazar_contactos boolean,
    p_contactos jsonb,
    p_reemplazar_participantes boolean,
    p_participantes jsonb,
    p_expected_updated_at timestamptz,
    p_campos_modificados text[],
    p_actor_user_id uuid,
    p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
    v_actor record;
    v_asignacion public.asignaciones%ROWTYPE;
    v_estado_codigo text;
    v_result jsonb;
    v_subresult jsonb;
    v_item jsonb;
    v_existente record;
    v_tipo_deseado uuid;
    v_pending uuid;
    v_old jsonb;
    v_new jsonb;
    v_nuevo_id uuid;
    v_old_historical_flag text;
    v_has_base_changes boolean;
BEGIN
    -- Actor y permisos.
    SELECT u.rol_id, r.codigo AS rol_codigo
    INTO v_actor
    FROM public.usuarios u
    JOIN public.roles r ON r.id=u.rol_id
    WHERE u.id=p_actor_user_id AND u.activo=true AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok',false,'error_code','ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS(
        SELECT 1 FROM public.rol_permiso rp
        JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_actor.rol_id AND p.codigo='UPDATE_ASSIGNMENT' AND p.activo=true
    ) THEN
        RETURN jsonb_build_object('ok',false,'error_code','FORBIDDEN');
    END IF;

    IF p_reemplazar_participantes AND NOT EXISTS(
        SELECT 1 FROM public.rol_permiso rp
        JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_actor.rol_id AND p.codigo='REASSIGN_ASSIGNMENT' AND p.activo=true
    ) THEN
        RETURN jsonb_build_object('ok',false,'error_code','FORBIDDEN');
    END IF;

    SELECT a.* INTO v_asignacion
    FROM public.asignaciones a
    WHERE a.id=p_asignacion_id AND a.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok',false,'error_code','ASSIGNMENT_NOT_FOUND');
    END IF;
    IF v_asignacion.activo IS NOT TRUE THEN
        RETURN jsonb_build_object('ok',false,'error_code','ASSIGNMENT_INACTIVE');
    END IF;
    IF v_asignacion.updated_at IS DISTINCT FROM p_expected_updated_at THEN
        RETURN jsonb_build_object('ok',false,'error_code','ASSIGNMENT_CHANGED');
    END IF;

    SELECT codigo INTO v_estado_codigo FROM public.estados_asignacion WHERE id=v_asignacion.estado_id;
    IF v_estado_codigo='CANCELADA' THEN
        RETURN jsonb_build_object('ok',false,'error_code','ASSIGNMENT_CLOSED');
    END IF;

    IF p_reemplazar_participantes THEN
        IF p_participantes IS NULL OR jsonb_typeof(p_participantes)<>'array' OR jsonb_array_length(p_participantes)=0 THEN
            RETURN jsonb_build_object('ok',false,'error_code','INVALID_PARTICIPANTS');
        END IF;
        IF (
            SELECT count(*) <> count(DISTINCT value->>'usuario_id')
            FROM jsonb_array_elements(p_participantes)
        ) THEN
            RETURN jsonb_build_object('ok',false,'error_code','INVALID_PARTICIPANTS');
        END IF;
        IF EXISTS(
            SELECT 1
            FROM jsonb_array_elements(p_participantes) x
            LEFT JOIN public.usuarios u ON u.id=(x.value->>'usuario_id')::uuid
            LEFT JOIN public.roles r ON r.id=u.rol_id
            LEFT JOIN public.tipos_participacion tp ON tp.id=(x.value->>'tipo_participacion_id')::uuid
            WHERE u.id IS NULL OR u.activo IS NOT TRUE OR u.deleted_at IS NOT NULL
               OR r.codigo NOT IN ('DIRECTIVA','COORDINADOR','MONITOR')
               OR tp.id IS NULL OR tp.activo IS NOT TRUE
        ) THEN
            RETURN jsonb_build_object('ok',false,'error_code','INVALID_PARTICIPANTS');
        END IF;
    END IF;

    v_has_base_changes := coalesce(p_cambios, '{}'::jsonb) <> '{}'::jsonb
                          OR p_reemplazar_contactos;

    -- Todo el bloque se comporta como subtransacción: un error funcional en
    -- participantes revierte también la actualización base.
    BEGIN
        IF v_estado_codigo='NO_REALIZADA' THEN
            -- Corrección histórica: no usa la RPC normal porque aquella está
            -- diseñada para reconfirmación de actividades abiertas.
            v_old_historical_flag:=coalesce(current_setting('huellapp.edicion_historica',true),'');
            PERFORM set_config('huellapp.edicion_historica','true',true);
            PERFORM set_config('huellapp.request_id',coalesce(p_request_id::text,''),true);
            PERFORM set_config('huellapp.ip_address',coalesce(p_ip_address::text,''),true);
            PERFORM set_config('huellapp.user_agent',coalesce(p_user_agent,''),true);

            SELECT to_jsonb(a) INTO v_old FROM public.asignaciones a WHERE a.id=p_asignacion_id;

            IF v_has_base_changes THEN
                UPDATE public.asignaciones
                SET colegio_id = CASE WHEN p_cambios ? 'colegio_id' THEN (p_cambios->>'colegio_id')::uuid ELSE colegio_id END,
                    coordinador_id = CASE WHEN p_cambios ? 'coordinador_id' THEN (p_cambios->>'coordinador_id')::uuid ELSE coordinador_id END,
                    curso_colegio_id = CASE WHEN p_cambios ? 'curso_colegio_id' THEN (p_cambios->>'curso_colegio_id')::uuid ELSE curso_colegio_id END,
                    ramo_id = CASE WHEN p_cambios ? 'ramo_id' THEN (p_cambios->>'ramo_id')::uuid ELSE ramo_id END,
                    espacio_reflexion_id = CASE WHEN p_cambios ? 'espacio_reflexion_id' THEN (p_cambios->>'espacio_reflexion_id')::uuid ELSE espacio_reflexion_id END,
                    espacio_encuentro_id = CASE WHEN p_cambios ? 'espacio_encuentro_id' THEN (p_cambios->>'espacio_encuentro_id')::uuid ELSE espacio_encuentro_id END,
                    fecha = CASE WHEN p_cambios ? 'fecha' THEN (p_cambios->>'fecha')::date ELSE fecha END,
                    hora_inicio = CASE WHEN p_cambios ? 'hora_inicio' THEN (p_cambios->>'hora_inicio')::time ELSE hora_inicio END,
                    hora_fin = CASE WHEN p_cambios ? 'hora_fin' THEN (p_cambios->>'hora_fin')::time ELSE hora_fin END,
                    lugar = CASE WHEN p_cambios ? 'lugar' THEN p_cambios->>'lugar' ELSE lugar END,
                    observacion = CASE WHEN p_cambios ? 'observacion' THEN p_cambios->>'observacion' ELSE observacion END,
                    updated_by=p_actor_user_id,
                    updated_at=now()
                WHERE id=p_asignacion_id;

                IF p_reemplazar_contactos THEN
                    IF p_contactos IS NULL OR jsonb_typeof(p_contactos)<>'array' THEN
                        RAISE EXCEPTION 'HUELLAPP_TX_ERROR:INVALID_CONTACTS';
                    END IF;
                    DELETE FROM public.asignacion_contactos WHERE asignacion_id=p_asignacion_id;
                    FOR v_item IN SELECT value FROM jsonb_array_elements(p_contactos)
                    LOOP
                        INSERT INTO public.asignacion_contactos(asignacion_id,contacto_colegio_id,created_by)
                        VALUES(p_asignacion_id,(v_item->>'contacto_colegio_id')::uuid,p_actor_user_id);
                    END LOOP;
                END IF;

                SELECT to_jsonb(a) INTO v_new FROM public.asignaciones a WHERE a.id=p_asignacion_id;
                INSERT INTO public.audit_logs(
                    actor_user_id,actor_role_id,action,entity_type,entity_id,
                    old_values,new_values,description,request_id,ip_address,user_agent,source
                ) VALUES(
                    p_actor_user_id,v_actor.rol_id,'UPDATE_ASSIGNMENT','ASSIGNMENT',p_asignacion_id,
                    v_old,v_new,'Corrección administrativa de instancia NO_REALIZADA.',
                    p_request_id,p_ip_address,p_user_agent,'WEB'
                );
            END IF;

            IF p_reemplazar_participantes THEN
                SELECT id INTO v_pending FROM public.estados_participacion WHERE codigo='PENDIENTE' AND activo LIMIT 1;
                IF v_pending IS NULL THEN
                    RAISE EXCEPTION 'HUELLAPP_TX_ERROR:PARTICIPANT_UPDATE_FAILED';
                END IF;

                -- Retirar o cambiar tipo conservando el registro anterior cuando
                -- ya existió una respuesta.
                FOR v_existente IN
                    SELECT ap.*, ep.codigo AS estado_codigo
                    FROM public.asignacion_participantes ap
                    JOIN public.estados_participacion ep ON ep.id=ap.estado_participacion_id
                    WHERE ap.asignacion_id=p_asignacion_id AND ap.activo AND ap.deleted_at IS NULL
                    ORDER BY ap.created_at,ap.id
                    FOR UPDATE OF ap
                LOOP
                    SELECT (x.value->>'tipo_participacion_id')::uuid
                    INTO v_tipo_deseado
                    FROM jsonb_array_elements(p_participantes) x
                    WHERE (x.value->>'usuario_id')::uuid=v_existente.usuario_id
                    LIMIT 1;

                    IF v_tipo_deseado IS NULL THEN
                        v_old:=to_jsonb(v_existente);
                        UPDATE public.asignacion_participantes
                        SET activo=false,deleted_at=now(),updated_by=p_actor_user_id,updated_at=now()
                        WHERE id=v_existente.id;
                        SELECT to_jsonb(ap) INTO v_new FROM public.asignacion_participantes ap WHERE ap.id=v_existente.id;
                        INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,description,request_id,ip_address,user_agent,source)
                        VALUES(p_actor_user_id,v_actor.rol_id,'REMOVE_PARTICIPANT','ASSIGNMENT_PARTICIPANT',v_existente.id,v_old,v_new,
                               'Participante retirado durante corrección administrativa de instancia NO_REALIZADA.',p_request_id,p_ip_address,p_user_agent,'WEB');
                    ELSIF v_tipo_deseado IS DISTINCT FROM v_existente.tipo_participacion_id THEN
                        v_old:=to_jsonb(v_existente);
                        IF v_existente.estado_codigo='PENDIENTE' THEN
                            UPDATE public.asignacion_participantes
                            SET tipo_participacion_id=v_tipo_deseado,updated_by=p_actor_user_id,updated_at=now()
                            WHERE id=v_existente.id;
                            SELECT to_jsonb(ap) INTO v_new FROM public.asignacion_participantes ap WHERE ap.id=v_existente.id;
                            v_nuevo_id:=v_existente.id;
                        ELSE
                            UPDATE public.asignacion_participantes
                            SET activo=false,deleted_at=now(),updated_by=p_actor_user_id,updated_at=now()
                            WHERE id=v_existente.id;
                            INSERT INTO public.asignacion_participantes(
                                asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,
                                motivo_rechazo,fecha_respuesta,respondido_por,activo,created_by,updated_by
                            ) VALUES(
                                p_asignacion_id,v_existente.usuario_id,v_tipo_deseado,v_pending,
                                NULL,NULL,NULL,true,p_actor_user_id,p_actor_user_id
                            ) RETURNING id INTO v_nuevo_id;
                            SELECT to_jsonb(ap) INTO v_new FROM public.asignacion_participantes ap WHERE ap.id=v_nuevo_id;
                        END IF;
                        INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,description,request_id,ip_address,user_agent,source)
                        VALUES(p_actor_user_id,v_actor.rol_id,'CHANGE_PARTICIPATION_TYPE','ASSIGNMENT_PARTICIPANT',v_nuevo_id,v_old,v_new,
                               'Tipo de participación corregido en instancia NO_REALIZADA.',p_request_id,p_ip_address,p_user_agent,'WEB');
                    END IF;
                END LOOP;

                -- Crear los participantes nuevos que no existan activos.
                FOR v_item IN SELECT value FROM jsonb_array_elements(p_participantes)
                LOOP
                    IF NOT EXISTS(
                        SELECT 1 FROM public.asignacion_participantes ap
                        WHERE ap.asignacion_id=p_asignacion_id
                          AND ap.usuario_id=(v_item->>'usuario_id')::uuid
                          AND ap.activo AND ap.deleted_at IS NULL
                    ) THEN
                        INSERT INTO public.asignacion_participantes(
                            asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,
                            motivo_rechazo,fecha_respuesta,respondido_por,activo,created_by,updated_by
                        ) VALUES(
                            p_asignacion_id,(v_item->>'usuario_id')::uuid,(v_item->>'tipo_participacion_id')::uuid,
                            v_pending,NULL,NULL,NULL,true,p_actor_user_id,p_actor_user_id
                        ) RETURNING id INTO v_nuevo_id;
                        SELECT to_jsonb(ap) INTO v_new FROM public.asignacion_participantes ap WHERE ap.id=v_nuevo_id;
                        INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,description,request_id,ip_address,user_agent,source)
                        VALUES(p_actor_user_id,v_actor.rol_id,'ADD_PARTICIPANT','ASSIGNMENT_PARTICIPANT',v_nuevo_id,NULL,v_new,
                               'Participante agregado durante corrección administrativa de instancia NO_REALIZADA.',p_request_id,p_ip_address,p_user_agent,'WEB');
                    END IF;
                END LOOP;

                UPDATE public.asignaciones
                SET updated_by=p_actor_user_id,updated_at=now()
                WHERE id=p_asignacion_id;
            END IF;

            PERFORM set_config('huellapp.edicion_historica',v_old_historical_flag,true);

        ELSE
            -- Flujo vigente para PENDIENTE/CONFIRMADA (y cambios no sustantivos
            -- permitidos por la lógica existente). La función 061 conserva la
            -- reconfirmación y la gestión del coordinador responsable.
            IF v_has_base_changes THEN
                v_result:=public.actualizar_asignacion_atomica(
                    p_asignacion_id,p_cambios,p_reemplazar_contactos,p_contactos,
                    p_expected_updated_at,array_remove(p_campos_modificados,'participantes'),
                    p_actor_user_id,p_request_id,p_ip_address,p_user_agent
                );
                IF v_result->>'ok'<>'true' THEN
                    RAISE EXCEPTION 'HUELLAPP_TX_ERROR:%',coalesce(v_result->>'error_code','PARTICIPANT_UPDATE_FAILED');
                END IF;
            END IF;

            IF p_reemplazar_participantes THEN
                -- Retira/cambia tipos de participantes actuales.
                FOR v_existente IN
                    SELECT ap.*
                    FROM public.asignacion_participantes ap
                    WHERE ap.asignacion_id=p_asignacion_id AND ap.activo AND ap.deleted_at IS NULL
                    ORDER BY ap.created_at,ap.id
                LOOP
                    SELECT (x.value->>'tipo_participacion_id')::uuid
                    INTO v_tipo_deseado
                    FROM jsonb_array_elements(p_participantes) x
                    WHERE (x.value->>'usuario_id')::uuid=v_existente.usuario_id
                    LIMIT 1;

                    IF v_tipo_deseado IS NULL THEN
                        v_subresult:=public.quitar_participante_atomico(
                            p_asignacion_id,v_existente.id,p_actor_user_id,p_request_id,p_ip_address,p_user_agent
                        );
                        IF v_subresult->>'ok'<>'true' THEN
                            RAISE EXCEPTION 'HUELLAPP_TX_ERROR:PARTICIPANT_UPDATE_FAILED';
                        END IF;
                    ELSIF v_tipo_deseado IS DISTINCT FROM v_existente.tipo_participacion_id THEN
                        v_subresult:=public.cambiar_tipo_participacion_atomico(
                            p_asignacion_id,v_existente.id,v_tipo_deseado,p_actor_user_id,p_request_id,p_ip_address,p_user_agent
                        );
                        IF v_subresult->>'ok'<>'true' THEN
                            RAISE EXCEPTION 'HUELLAPP_TX_ERROR:PARTICIPANT_UPDATE_FAILED';
                        END IF;
                    END IF;
                END LOOP;

                -- Agrega quienes no estaban activos.
                FOR v_item IN SELECT value FROM jsonb_array_elements(p_participantes)
                LOOP
                    IF NOT EXISTS(
                        SELECT 1 FROM public.asignacion_participantes ap
                        WHERE ap.asignacion_id=p_asignacion_id
                          AND ap.usuario_id=(v_item->>'usuario_id')::uuid
                          AND ap.activo AND ap.deleted_at IS NULL
                    ) THEN
                        v_subresult:=public.agregar_participante_atomico(
                            p_asignacion_id,(v_item->>'usuario_id')::uuid,(v_item->>'tipo_participacion_id')::uuid,
                            p_actor_user_id,p_request_id,p_ip_address,p_user_agent
                        );
                        IF v_subresult->>'ok'<>'true' THEN
                            RAISE EXCEPTION 'HUELLAPP_TX_ERROR:PARTICIPANT_UPDATE_FAILED';
                        END IF;
                    END IF;
                END LOOP;
            END IF;
        END IF;

    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'HUELLAPP_TX_ERROR:%' THEN
            RETURN jsonb_build_object('ok',false,'error_code',split_part(SQLERRM,':',2));
        END IF;
        RAISE;
    END;

    RETURN jsonb_build_object('ok',true,'asignacion_id',p_asignacion_id);
END;
$$;

COMMENT ON FUNCTION public.actualizar_asignacion_completa_atomica(
    uuid,jsonb,boolean,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) IS
'Actualiza datos, contactos y participantes de una instancia en una sola transacción. NO_REALIZADA se corrige administrativamente sin cambiar estado ni reenviar invitaciones.';

REVOKE ALL ON FUNCTION public.actualizar_asignacion_completa_atomica(
    uuid,jsonb,boolean,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_asignacion_completa_atomica(
    uuid,jsonb,boolean,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
