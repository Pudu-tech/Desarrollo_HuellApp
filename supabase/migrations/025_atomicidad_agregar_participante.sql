-- ============================================================
-- HuellAPP
-- Migración 025
-- Agregar participante de forma atómica
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Ejecutar en una sola transacción:
--
-- - validar actor y permiso REASSIGN_ASSIGNMENT;
-- - validar asignación;
-- - validar usuario participante;
-- - validar tipo de participación;
-- - impedir participación activa duplicada;
-- - crear participación PENDIENTE;
-- - permitir que el trigger cree su asistencia PENDIENTE;
-- - registrar auditoría ADD_PARTICIPANT.
--
-- Si cualquier paso falla, PostgreSQL revierte toda la operación.
-- ============================================================

BEGIN;


CREATE OR REPLACE FUNCTION public.agregar_participante_atomico(
    p_asignacion_id uuid,
    p_usuario_id uuid,
    p_tipo_participacion_id uuid,
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
    v_usuario record;

    v_estado_pendiente_id uuid;
    v_participante_id uuid;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
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
          AND p.codigo = 'REASSIGN_ASSIGNMENT'
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
    -- El bloqueo serializa operaciones concurrentes sobre la
    -- misma asignación y evita duplicados por carrera.
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
        'REALIZADA',
        'CANCELADA',
        'NO_REALIZADA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CLOSED'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR USUARIO PARTICIPANTE
    -- --------------------------------------------------------

    SELECT
        u.id,
        u.activo,
        u.deleted_at,
        r.codigo AS rol_codigo
    INTO v_usuario
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_usuario_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPANT_USER_NOT_FOUND'
        );
    END IF;

    IF v_usuario.activo IS NOT TRUE
       OR v_usuario.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPANT_USER_INACTIVE'
        );
    END IF;

    IF v_usuario.rol_codigo NOT IN (
        'DIRECTIVA',
        'COORDINADOR',
        'MONITOR'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_PARTICIPANT_ROLE'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR TIPO DE PARTICIPACIÓN
    -- --------------------------------------------------------

    IF NOT EXISTS (
        SELECT 1
        FROM public.tipos_participacion tp
        WHERE tp.id = p_tipo_participacion_id
          AND tp.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_TYPE_NOT_FOUND'
        );
    END IF;


    -- --------------------------------------------------------
    -- EVITAR PARTICIPACIÓN ACTIVA DUPLICADA
    -- --------------------------------------------------------

    IF EXISTS (
        SELECT 1
        FROM public.asignacion_participantes ap
        WHERE ap.asignacion_id = p_asignacion_id
          AND ap.usuario_id = p_usuario_id
          AND ap.activo = true
          AND ap.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ACTIVE_PARTICIPATION_EXISTS'
        );
    END IF;


    -- --------------------------------------------------------
    -- OBTENER ESTADO PENDIENTE
    -- --------------------------------------------------------

    SELECT ep.id
    INTO v_estado_pendiente_id
    FROM public.estados_participacion ep
    WHERE ep.codigo = 'PENDIENTE'
      AND ep.activo = true
    LIMIT 1;

    IF v_estado_pendiente_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PENDING_STATE_NOT_FOUND'
        );
    END IF;


    -- --------------------------------------------------------
    -- CREAR PARTICIPACIÓN
    -- --------------------------------------------------------
    -- El trigger existente de asignacion_participantes crea
    -- automáticamente la asistencia PENDIENTE correspondiente.
    -- --------------------------------------------------------

    INSERT INTO public.asignacion_participantes (
        asignacion_id,
        usuario_id,
        tipo_participacion_id,
        estado_participacion_id,
        motivo_rechazo,
        fecha_respuesta,
        respondido_por,
        activo,
        created_by,
        updated_by
    )
    VALUES (
        p_asignacion_id,
        p_usuario_id,
        p_tipo_participacion_id,
        v_estado_pendiente_id,
        NULL,
        NULL,
        NULL,
        true,
        p_actor_user_id,
        p_actor_user_id
    )
    RETURNING id
    INTO v_participante_id;


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
        'ADD_PARTICIPANT',
        'ASSIGNMENT_PARTICIPANT',
        v_participante_id,
        NULL,
        jsonb_build_object(
            'id', v_participante_id,
            'asignacion_id', p_asignacion_id,
            'usuario_id', p_usuario_id,
            'tipo_participacion_id',
                p_tipo_participacion_id,
            'estado_participacion_id',
                v_estado_pendiente_id,
            'motivo_rechazo', NULL,
            'fecha_respuesta', NULL,
            'respondido_por', NULL,
            'activo', true
        ),
        'Participante agregado a la asignación.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'participante_id', v_participante_id
    );
END;
$$;


COMMENT ON FUNCTION public.agregar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) IS
'Agrega un participante PENDIENTE a una asignación de forma atómica, incluyendo su asistencia automática y auditoría.';


-- ============================================================
-- SEGURIDAD
-- ============================================================

REVOKE ALL ON FUNCTION public.agregar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.agregar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.agregar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.agregar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;