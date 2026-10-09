-- 048 · Edición sustantiva: respuesta pendiente, auditoría y una invitación nueva.
-- Aplicar después de 047; no altera invitaciones ni respuestas anteriores al cambio.
BEGIN;
CREATE OR REPLACE FUNCTION public.renovar_invitaciones_asignacion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_changed boolean; v_pending uuid; v_pending_assignment uuid; v_part record; v_new jsonb; v_role uuid;
BEGIN
 v_changed:= NEW.fecha IS DISTINCT FROM OLD.fecha OR NEW.hora_inicio IS DISTINCT FROM OLD.hora_inicio
 OR NEW.hora_fin IS DISTINCT FROM OLD.hora_fin OR NEW.colegio_id IS DISTINCT FROM OLD.colegio_id
 OR NEW.curso_colegio_id IS DISTINCT FROM OLD.curso_colegio_id OR NEW.sala_id IS DISTINCT FROM OLD.sala_id
 OR NEW.ramo_id IS DISTINCT FROM OLD.ramo_id OR NEW.espacio_reflexion_id IS DISTINCT FROM OLD.espacio_reflexion_id
 OR NEW.espacio_encuentro_id IS DISTINCT FROM OLD.espacio_encuentro_id OR NEW.lugar IS DISTINCT FROM OLD.lugar
 OR NEW.tipo_actividad_id IS DISTINCT FROM OLD.tipo_actividad_id;
 IF v_changed THEN
   IF NOT NEW.activo OR NEW.deleted_at IS NOT NULL
      OR NOT EXISTS(SELECT 1 FROM public.estados_asignacion WHERE id=OLD.estado_id AND codigo IN ('PENDIENTE','CONFIRMADA'))
      OR NOT EXISTS(SELECT 1 FROM public.estados_asignacion WHERE id=NEW.estado_id AND codigo IN ('PENDIENTE','CONFIRMADA'))
      OR (OLD.fecha+OLD.hora_fin) AT TIME ZONE 'America/Santiago'<=now()
      OR (NEW.fecha+NEW.hora_fin) AT TIME ZONE 'America/Santiago'<=now()
      OR EXISTS(SELECT 1 FROM public.asistencias_asignacion s JOIN public.asignacion_participantes p ON p.id=s.asignacion_participante_id
         WHERE p.asignacion_id=NEW.id AND s.estado<>'PENDIENTE') THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ASSIGNMENT_RECONFIRMATION_UNAVAILABLE';
   END IF;
   IF current_setting('huellapp.edicion_rpc',true) IS DISTINCT FROM 'true' THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ASSIGNMENT_RECONFIRMATION_UNAVAILABLE';
   END IF;
   SELECT id INTO v_pending FROM public.estados_participacion WHERE codigo='PENDIENTE' AND activo;
   SELECT id INTO v_pending_assignment FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
   IF v_pending IS NULL OR v_pending_assignment IS NULL THEN RAISE EXCEPTION 'Faltan estados PENDIENTE activos'; END IF;
   SELECT rol_id INTO v_role FROM public.usuarios WHERE id=NEW.updated_by;
   FOR v_part IN SELECT * FROM public.asignacion_participantes WHERE asignacion_id=NEW.id AND activo AND deleted_at IS NULL ORDER BY id FOR UPDATE LOOP
     UPDATE public.asignacion_participantes SET estado_participacion_id=v_pending,motivo_rechazo=NULL,
       fecha_respuesta=NULL,respondido_por=NULL,invitacion_version=gen_random_uuid(),updated_at=now(),updated_by=NEW.updated_by
     WHERE id=v_part.id RETURNING to_jsonb(asignacion_participantes) INTO v_new;
     UPDATE public.notificaciones SET titulo='Asignación actualizada en HuellApp',
       mensaje='Las condiciones de la actividad cambiaron. Confirma nuevamente tu participación.'
     WHERE participacion_id=v_part.id AND invitacion_version=(v_new->>'invitacion_version')::uuid;
     INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,
       description,request_id,ip_address,user_agent,source)
     VALUES(NEW.updated_by,v_role,'REQUEST_PARTICIPATION_RECONFIRMATION','ASSIGNMENT_PARTICIPANT',v_part.id,
       to_jsonb(v_part),v_new,'Reconfirmación por cambio de condiciones de la asignación.',
       nullif(current_setting('huellapp.request_id',true),'')::uuid,
       nullif(current_setting('huellapp.ip_address',true),'')::inet,
       nullif(current_setting('huellapp.user_agent',true),''),'WEB');
   END LOOP;
   -- La RPC cambia el estado después de reemplazar contactos. Si cambió el
   -- colegio, validar los contactos antiguos al pasar a PENDIENTE sería incorrecto.
   PERFORM set_config('huellapp.reconfirm_assignment',NEW.id::text,true);
 ELSIF (NEW.activo AND NOT OLD.activo) OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
 OR (NEW.estado_id IS DISTINCT FROM OLD.estado_id AND EXISTS(SELECT 1 FROM public.estados_asignacion
    WHERE id=OLD.estado_id AND codigo NOT IN ('PENDIENTE','CONFIRMADA'))) THEN
   UPDATE public.asignacion_participantes SET invitacion_version=gen_random_uuid()
   WHERE asignacion_id=NEW.id AND activo AND deleted_at IS NULL;
 END IF;
 RETURN NEW;
END;
$$;

-- Conserva la RPC 029 y su control optimista; transmite contexto a sus triggers.
ALTER FUNCTION public.actualizar_asignacion_atomica(uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text)
RENAME TO actualizar_asignacion_base_048;
REVOKE ALL ON FUNCTION public.actualizar_asignacion_base_048(uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text)
FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.actualizar_asignacion_atomica(
 p_asignacion_id uuid,p_cambios jsonb,p_reemplazar_contactos boolean,p_contactos jsonb,
 p_expected_updated_at timestamptz,p_campos_modificados text[],p_actor_user_id uuid,
 p_request_id uuid DEFAULT NULL,p_ip_address inet DEFAULT NULL,p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_result jsonb; v_request text; v_ip text; v_agent text; v_rpc text; v_flag text;
 v_pending uuid; v_actual public.asignaciones%ROWTYPE; v_new jsonb; v_role uuid;
BEGIN
 v_request:=coalesce(current_setting('huellapp.request_id',true),'');
 v_ip:=coalesce(current_setting('huellapp.ip_address',true),'');
 v_agent:=coalesce(current_setting('huellapp.user_agent',true),'');
 v_rpc:=coalesce(current_setting('huellapp.edicion_rpc',true),'');
 v_flag:=coalesce(current_setting('huellapp.reconfirm_assignment',true),'');
 PERFORM set_config('huellapp.edicion_rpc','true',true);
 PERFORM set_config('huellapp.reconfirm_assignment','',true);
 PERFORM set_config('huellapp.request_id',coalesce(p_request_id::text,''),true);
 PERFORM set_config('huellapp.ip_address',coalesce(p_ip_address::text,''),true);
 PERFORM set_config('huellapp.user_agent',coalesce(p_user_agent,''),true);
 v_result:=public.actualizar_asignacion_base_048(p_asignacion_id,p_cambios,p_reemplazar_contactos,p_contactos,
   p_expected_updated_at,p_campos_modificados,p_actor_user_id,p_request_id,p_ip_address,p_user_agent);
 IF v_result->>'ok'='true' AND current_setting('huellapp.reconfirm_assignment',true)=p_asignacion_id::text THEN
   SELECT * INTO v_actual FROM public.asignaciones WHERE id=p_asignacion_id;
   SELECT id INTO v_pending FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
   IF v_actual.estado_id<>v_pending THEN
     UPDATE public.asignaciones SET estado_id=v_pending WHERE id=p_asignacion_id RETURNING to_jsonb(asignaciones) INTO v_new;
     SELECT rol_id INTO v_role FROM public.usuarios WHERE id=p_actor_user_id;
     INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,
       description,request_id,ip_address,user_agent,source)
     VALUES(p_actor_user_id,v_role,'REQUEST_ASSIGNMENT_RECONFIRMATION','ASSIGNMENT',p_asignacion_id,to_jsonb(v_actual),v_new,
       'Asignación vuelve a Pendiente por cambio de condiciones.',p_request_id,p_ip_address,p_user_agent,'WEB');
   END IF;
 END IF;
 PERFORM set_config('huellapp.request_id',v_request,true);
 PERFORM set_config('huellapp.ip_address',v_ip,true);
 PERFORM set_config('huellapp.user_agent',v_agent,true);
 PERFORM set_config('huellapp.edicion_rpc',v_rpc,true);
 PERFORM set_config('huellapp.reconfirm_assignment',v_flag,true);
 RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.actualizar_asignacion_atomica(uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_asignacion_atomica(uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text) TO service_role;
COMMIT;
