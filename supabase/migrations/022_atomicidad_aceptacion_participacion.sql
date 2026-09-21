-- ============================================================
-- HuellAPP
-- Migración 022
-- Aceptación atómica de participación
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Evitar estados parciales cuando un participante acepta una asignación.
--
-- La operación se ejecuta en una sola transacción PostgreSQL:
-- - valida actor, permiso, asignación y participación;
-- - cambia la participación PENDIENTE a ACEPTADA;
-- - registra la auditoría de la aceptación;
-- - si el participante es RELATOR y la asignación está PENDIENTE,
--   cambia la asignación a CONFIRMADA;
-- - registra la auditoría de la confirmación automática.
--
-- Si cualquier escritura falla, PostgreSQL revierte toda la operación.
-- La RPC queda disponible exclusivamente para service_role.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FUNCIÓN TRANSACCIONAL
-- ============================================================

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

    IF v_asignacion.estado_codigo NOT IN (
        'PENDIENTE',
        'CONFIRMADA'
    ) THEN
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


COMMENT ON FUNCTION public.aceptar_participacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) IS
'Acepta una participación PENDIENTE de forma atómica y confirma la asignación cuando acepta un RELATOR sobre una asignación PENDIENTE.';


-- ============================================================
-- 2. RESTRINGIR EJECUCIÓN DE LA RPC
-- ============================================================

REVOKE ALL ON FUNCTION public.aceptar_participacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.aceptar_participacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.aceptar_participacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.aceptar_participacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;
