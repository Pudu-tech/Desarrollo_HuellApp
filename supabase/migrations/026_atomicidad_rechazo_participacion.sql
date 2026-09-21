-- ============================================================
-- HuellAPP
-- Migración 026
-- Rechazo atómico de participación
-- ============================================================

BEGIN;


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

    IF v_asignacion.estado_codigo IN (
        'CANCELADA',
        'REALIZADA',
        'NO_REALIZADA'
    ) THEN

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


COMMENT ON FUNCTION public.rechazar_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) IS
'Rechaza una participación PENDIENTE de forma atómica y registra su auditoría.';


REVOKE ALL ON FUNCTION public.rechazar_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.rechazar_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.rechazar_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.rechazar_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;