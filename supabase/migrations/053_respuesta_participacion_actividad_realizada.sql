-- Respuesta individual hasta 24 horas después del término, incluso si otro participante ya informó presencia.
BEGIN;
CREATE OR REPLACE FUNCTION public.aceptar_participacion_atomica(
    p_asignacion_id uuid,
    p_participante_id uuid,
    p_actor_user_id uuid,
    p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor record;
    v_asignacion record;
    v_participacion record;

    v_estado_aceptada_id uuid;
    v_estado_confirmada_id uuid;
    v_asignacion_confirmada boolean := false;

    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
    -- --------------------------------------------------------
    -- FastAPI exige ACCEPT_PARTICIPATION. La validación se repite
    -- en PostgreSQL porque esta función utiliza SECURITY DEFINER.
    -- --------------------------------------------------------

    SELECT
        u.rol_id,
        r.codigo AS rol_codigo
    INTO v_actor
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ACTOR_NOT_FOUND'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
            ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'ACCEPT_PARTICIPATION'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;


    -- --------------------------------------------------------
    -- BLOQUEAR Y VALIDAR ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT
        a.id,
        a.estado_id,
        a.fecha,
        a.hora_fin,
        a.activo,
        a.deleted_at,
        ea.codigo AS estado_codigo
    INTO v_asignacion
    FROM public.asignaciones a
    JOIN public.estados_asignacion ea
        ON ea.id = a.estado_id
    WHERE a.id = p_asignacion_id
    FOR UPDATE OF a;

    IF NOT FOUND
       OR v_asignacion.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_NOT_FOUND'
        );
    END IF;

    IF v_asignacion.activo IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_INACTIVE'
        );
    END IF;

    IF v_asignacion.estado_codigo NOT IN ('PENDIENTE','CONFIRMADA','REALIZADA')
       OR now() >= ((v_asignacion.fecha + v_asignacion.hora_fin) AT TIME ZONE 'America/Santiago') + interval '24 hours' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CLOSED'
        );
    END IF;


    -- --------------------------------------------------------
    -- BLOQUEAR Y VALIDAR PARTICIPACIÓN
    -- --------------------------------------------------------

    SELECT
        ap.id,
        ap.asignacion_id,
        ap.usuario_id,
        ap.tipo_participacion_id,
        ap.estado_participacion_id,
        ap.motivo_rechazo,
        ap.fecha_respuesta,
        ap.respondido_por,
        ap.activo,
        tp.codigo AS tipo_codigo,
        ep.codigo AS estado_codigo
    INTO v_participacion
    FROM public.asignacion_participantes ap
    JOIN public.tipos_participacion tp
        ON tp.id = ap.tipo_participacion_id
    JOIN public.estados_participacion ep
        ON ep.id = ap.estado_participacion_id
    WHERE ap.id = p_participante_id
      AND ap.asignacion_id = p_asignacion_id
      AND ap.activo = true
      AND ap.deleted_at IS NULL
    FOR UPDATE OF ap;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPANT_NOT_FOUND'
        );
    END IF;

    -- La respuesta siempre pertenece al propio participante.
    IF v_participacion.usuario_id <> p_actor_user_id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NOT_PARTICIPANT_OWNER'
        );
    END IF;

    IF v_participacion.estado_codigo <> 'PENDIENTE' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_ALREADY_RESPONDED'
        );
    END IF;


    -- --------------------------------------------------------
    -- OBTENER ESTADO ACEPTADA
    -- --------------------------------------------------------

    SELECT ep.id
    INTO v_estado_aceptada_id
    FROM public.estados_participacion ep
    WHERE ep.codigo = 'ACEPTADA'
      AND ep.activo = true
    LIMIT 1;

    IF v_estado_aceptada_id IS NULL THEN
        RAISE EXCEPTION
            'No existe un estado de participación ACEPTADA activo.';
    END IF;


    -- --------------------------------------------------------
    -- PREPARAR AUDITORÍA Y ACEPTAR PARTICIPACIÓN
    -- --------------------------------------------------------

    v_old_values := jsonb_build_object(
        'id', v_participacion.id,
        'usuario_id', v_participacion.usuario_id,
        'tipo_participacion_id', v_participacion.tipo_participacion_id,
        'estado_participacion_id', v_participacion.estado_participacion_id,
        'motivo_rechazo', v_participacion.motivo_rechazo,
        'fecha_respuesta', v_participacion.fecha_respuesta,
        'respondido_por', v_participacion.respondido_por,
        'activo', v_participacion.activo
    );

    UPDATE public.asignacion_participantes
    SET
        estado_participacion_id = v_estado_aceptada_id,
        motivo_rechazo = NULL,
        fecha_respuesta = CURRENT_TIMESTAMP,
        respondido_por = p_actor_user_id,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_participante_id
      AND asignacion_id = p_asignacion_id
      AND estado_participacion_id = v_participacion.estado_participacion_id
      AND activo = true
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_CHANGED'
        );
    END IF;

    SELECT jsonb_build_object(
        'id', ap.id,
        'usuario_id', ap.usuario_id,
        'tipo_participacion_id', ap.tipo_participacion_id,
        'estado_participacion_id', ap.estado_participacion_id,
        'motivo_rechazo', ap.motivo_rechazo,
        'fecha_respuesta', ap.fecha_respuesta,
        'respondido_por', ap.respondido_por,
        'activo', ap.activo
    )
    INTO v_new_values
    FROM public.asignacion_participantes ap
    WHERE ap.id = p_participante_id;

    INSERT INTO public.audit_logs (
        actor_user_id,
        actor_role_id,
        action,
        entity_type,
        entity_id,
        old_values,
        new_values,
        description,
        request_id,
        ip_address,
        user_agent,
        source
    )
    VALUES (
        p_actor_user_id,
        v_actor.rol_id,
        'ACCEPT_PARTICIPATION',
        'ASSIGNMENT_PARTICIPANT',
        p_participante_id,
        v_old_values,
        v_new_values,
        'El participante aceptó su participación en la asignación.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    -- --------------------------------------------------------
    -- PENDIENTE -> CONFIRMADA SI ACEPTÓ UN RELATOR
    -- --------------------------------------------------------

    IF v_participacion.tipo_codigo = 'RELATOR'
       AND v_asignacion.estado_codigo = 'PENDIENTE' THEN

        SELECT ea.id
        INTO v_estado_confirmada_id
        FROM public.estados_asignacion ea
        WHERE ea.codigo = 'CONFIRMADA'
          AND ea.activo = true
        LIMIT 1;

        IF v_estado_confirmada_id IS NULL THEN
            RAISE EXCEPTION
                'No existe un estado de asignación CONFIRMADA activo.';
        END IF;

        UPDATE public.asignaciones
        SET
            estado_id = v_estado_confirmada_id,
            updated_by = p_actor_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_asignacion_id
          AND estado_id = v_asignacion.estado_id
          AND activo = true
          AND deleted_at IS NULL;

        IF FOUND THEN
            v_asignacion_confirmada := true;

            INSERT INTO public.audit_logs (
                actor_user_id,
                actor_role_id,
                action,
                entity_type,
                entity_id,
                old_values,
                new_values,
                description,
                request_id,
                ip_address,
                user_agent,
                source
            )
            VALUES (
                p_actor_user_id,
                v_actor.rol_id,
                'CONFIRM_ASSIGNMENT',
                'ASSIGNMENT',
                p_asignacion_id,
                jsonb_build_object(
                    'estado', 'PENDIENTE',
                    'estado_id', v_asignacion.estado_id
                ),
                jsonb_build_object(
                    'estado', 'CONFIRMADA',
                    'estado_id', v_estado_confirmada_id
                ),
                'Asignación confirmada automáticamente por aceptación de un RELATOR.',
                p_request_id,
                p_ip_address,
                p_user_agent,
                'WEB'
            );
        END IF;
    END IF;


    RETURN jsonb_build_object(
        'ok', true,
        'participante_id', p_participante_id,
        'asignacion_confirmada', v_asignacion_confirmada
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rechazar_participacion_atomica(
    p_asignacion_id uuid,
    p_participante_id uuid,
    p_motivo text,
    p_actor_user_id uuid,
    p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor record;
    v_asignacion record;
    v_participacion record;

    v_estado_rechazada_id uuid;

    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- MOTIVO OBLIGATORIO
    -- --------------------------------------------------------

    IF p_motivo IS NULL
       OR length(trim(p_motivo)) = 0 THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_REJECTION_REASON'
        );

    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
    -- --------------------------------------------------------

    SELECT
        u.id,
        u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ACTOR_NOT_FOUND'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
            ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'REJECT_PARTICIPATION'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT
        a.id,
        a.estado_id,
        a.fecha,
        a.hora_fin,
        a.activo,
        a.deleted_at,
        ea.codigo AS estado_codigo
    INTO v_asignacion
    FROM public.asignaciones a
    JOIN public.estados_asignacion ea
        ON ea.id = a.estado_id
    WHERE a.id = p_asignacion_id
    FOR UPDATE OF a;

    IF NOT FOUND
       OR v_asignacion.deleted_at IS NOT NULL THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_NOT_FOUND'
        );

    END IF;

    IF v_asignacion.activo IS NOT TRUE THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_INACTIVE'
        );

    END IF;

    IF v_asignacion.estado_codigo NOT IN ('PENDIENTE','CONFIRMADA','REALIZADA')
       OR now() >= ((v_asignacion.fecha + v_asignacion.hora_fin) AT TIME ZONE 'America/Santiago') + interval '24 hours' THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CLOSED'
        );

    END IF;


    -- --------------------------------------------------------
    -- VALIDAR PARTICIPACIÓN
    -- --------------------------------------------------------

    SELECT
        ap.id,
        ap.usuario_id,
        ap.tipo_participacion_id,
        ap.estado_participacion_id,
        ap.motivo_rechazo,
        ap.fecha_respuesta,
        ap.respondido_por,
        ap.activo,
        ep.codigo AS estado_codigo
    INTO v_participacion
    FROM public.asignacion_participantes ap
    JOIN public.estados_participacion ep
        ON ep.id = ap.estado_participacion_id
    WHERE ap.id = p_participante_id
      AND ap.asignacion_id = p_asignacion_id
      AND ap.activo = true
      AND ap.deleted_at IS NULL
    FOR UPDATE OF ap;

    IF NOT FOUND THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_NOT_FOUND'
        );

    END IF;


    -- Solo el propio participante puede responder.
    IF v_participacion.usuario_id <> p_actor_user_id THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NOT_PARTICIPANT_OWNER'
        );

    END IF;

    IF v_participacion.estado_codigo <> 'PENDIENTE' THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_ALREADY_RESPONDED'
        );

    END IF;


    -- --------------------------------------------------------
    -- OBTENER ESTADO RECHAZADA
    -- --------------------------------------------------------

    SELECT ep.id
    INTO v_estado_rechazada_id
    FROM public.estados_participacion ep
    WHERE ep.codigo = 'RECHAZADA'
      AND ep.activo = true
    LIMIT 1;

    IF v_estado_rechazada_id IS NULL THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'REJECTED_STATE_NOT_FOUND'
        );

    END IF;


    -- --------------------------------------------------------
    -- VALORES ANTERIORES PARA AUDITORÍA
    -- --------------------------------------------------------

    v_old_values := jsonb_build_object(
        'id', v_participacion.id,
        'usuario_id', v_participacion.usuario_id,
        'tipo_participacion_id',
            v_participacion.tipo_participacion_id,
        'estado_participacion_id',
            v_participacion.estado_participacion_id,
        'motivo_rechazo',
            v_participacion.motivo_rechazo,
        'fecha_respuesta',
            v_participacion.fecha_respuesta,
        'respondido_por',
            v_participacion.respondido_por,
        'activo',
            v_participacion.activo
    );


    -- --------------------------------------------------------
    -- RECHAZAR PARTICIPACIÓN
    -- --------------------------------------------------------

    UPDATE public.asignacion_participantes
    SET
        estado_participacion_id =
            v_estado_rechazada_id,
        motivo_rechazo =
            trim(p_motivo),
        fecha_respuesta =
            CURRENT_TIMESTAMP,
        respondido_por =
            p_actor_user_id,
        updated_by =
            p_actor_user_id,
        updated_at =
            CURRENT_TIMESTAMP
    WHERE id = p_participante_id
      AND estado_participacion_id =
          v_participacion.estado_participacion_id
      AND activo = true
      AND deleted_at IS NULL;

    IF NOT FOUND THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_CHANGED'
        );

    END IF;


    -- --------------------------------------------------------
    -- VALORES NUEVOS PARA AUDITORÍA
    -- --------------------------------------------------------

    SELECT jsonb_build_object(
        'id', ap.id,
        'usuario_id', ap.usuario_id,
        'tipo_participacion_id',
            ap.tipo_participacion_id,
        'estado_participacion_id',
            ap.estado_participacion_id,
        'motivo_rechazo',
            ap.motivo_rechazo,
        'fecha_respuesta',
            ap.fecha_respuesta,
        'respondido_por',
            ap.respondido_por,
        'activo',
            ap.activo
    )
    INTO v_new_values
    FROM public.asignacion_participantes ap
    WHERE ap.id = p_participante_id;


    -- --------------------------------------------------------
    -- AUDITORÍA
    -- --------------------------------------------------------

    INSERT INTO public.audit_logs (
        actor_user_id,
        actor_role_id,
        action,
        entity_type,
        entity_id,
        old_values,
        new_values,
        description,
        request_id,
        ip_address,
        user_agent,
        source
    )
    VALUES (
        p_actor_user_id,
        v_actor.rol_id,
        'REJECT_PARTICIPATION',
        'ASSIGNMENT_PARTICIPANT',
        p_participante_id,
        v_old_values,
        v_new_values,
        'El participante rechazó su participación en la asignación.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'participante_id', p_participante_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.responder_participacion_canal_atomica(
 p_asignacion_id uuid,p_participante_id uuid,p_actor_user_id uuid,p_accion text,p_canal text,
 p_version uuid DEFAULT NULL,p_motivo text DEFAULT NULL,p_request_id uuid DEFAULT NULL,
 p_ip_address inet DEFAULT NULL,p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_a record; v_p record; v_result jsonb; v_rol uuid;
BEGIN
 IF p_accion IS NULL OR p_accion NOT IN ('ACCEPT','REJECT') OR p_canal IS NULL OR p_canal NOT IN ('WEB','EMAIL') THEN
   RETURN jsonb_build_object('ok',false,'error_code','INVALID_RESPONSE'); END IF;
 SELECT a.*,e.codigo AS estado INTO v_a FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id=a.estado_id
 WHERE a.id=p_asignacion_id FOR UPDATE OF a;
 IF NOT FOUND OR NOT v_a.activo OR v_a.deleted_at IS NOT NULL OR v_a.estado NOT IN ('PENDIENTE','CONFIRMADA','REALIZADA') OR now() >= ((v_a.fecha + v_a.hora_fin) AT TIME ZONE 'America/Santiago') + interval '24 hours' THEN
   RETURN jsonb_build_object('ok',false,'error_code','ASSIGNMENT_CLOSED'); END IF;
 SELECT p.*,e.codigo AS estado INTO v_p FROM public.asignacion_participantes p JOIN public.estados_participacion e ON e.id=p.estado_participacion_id
 WHERE p.id=p_participante_id AND p.asignacion_id=p_asignacion_id FOR UPDATE OF p;
 IF NOT FOUND OR NOT v_p.activo OR v_p.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error_code','PARTICIPANT_NOT_FOUND'); END IF;
 IF v_p.usuario_id<>p_actor_user_id OR NOT EXISTS(SELECT 1 FROM public.usuarios WHERE id=p_actor_user_id AND activo AND deleted_at IS NULL) THEN
   RETURN jsonb_build_object('ok',false,'error_code','NOT_PARTICIPANT_OWNER'); END IF;
 IF p_canal='EMAIL' AND (p_version IS NULL OR p_version IS DISTINCT FROM v_p.invitacion_version
    OR NOT EXISTS(SELECT 1 FROM public.notificaciones WHERE participacion_id=v_p.id AND invitacion_version=p_version
       AND usuario_destino_id=p_actor_user_id AND expires_at>now())) THEN
   RETURN jsonb_build_object('ok',false,'error_code','INVITATION_EXPIRED'); END IF;
 IF v_p.estado<>'PENDIENTE' THEN
   RETURN jsonb_build_object('ok',true,'ya_respondida',true,'estado',v_p.estado); END IF;
 IF p_accion='ACCEPT' THEN
   v_result:=public.aceptar_participacion_atomica(p_asignacion_id,p_participante_id,p_actor_user_id,p_request_id,p_ip_address,p_user_agent);
 ELSE
   v_result:=public.rechazar_participacion_atomica(p_asignacion_id,p_participante_id,p_motivo,p_actor_user_id,p_request_id,p_ip_address,p_user_agent);
 END IF;
 IF v_result->>'ok'<>'true' THEN RETURN v_result; END IF;
 SELECT rol_id INTO v_rol FROM public.usuarios WHERE id=p_actor_user_id;
 INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,
   description,request_id,ip_address,user_agent,source)
 VALUES(p_actor_user_id,v_rol,'PARTICIPATION_RESPONSE_CHANNEL','ASSIGNMENT_PARTICIPANT',p_participante_id,
   jsonb_build_object('estado','PENDIENTE'),jsonb_build_object('estado',CASE p_accion WHEN 'ACCEPT' THEN 'ACEPTADA' ELSE 'RECHAZADA' END,'canal',p_canal),
   'Respuesta única a una invitación de participación.',p_request_id,p_ip_address,p_user_agent,p_canal);
 RETURN v_result || jsonb_build_object('estado',CASE p_accion WHEN 'ACCEPT' THEN 'ACEPTADA' ELSE 'RECHAZADA' END,'ya_respondida',false);
END;
$$;
COMMIT;
