-- ============================================================
-- HuellAPP
-- Migración 020
-- Reapertura atómica de participaciones rechazadas
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Evitar estados parciales al reabrir una participación RECHAZADA.
--
-- La función centraliza en una sola transacción PostgreSQL:
-- - validación del actor y permiso REASSIGN_ASSIGNMENT;
-- - validación de asignación y participación;
-- - archivado de la participación rechazada;
-- - creación de una nueva participación PENDIENTE para el mismo usuario
--   y tipo de participación;
-- - creación automática de asistencia PENDIENTE mediante el trigger existente;
-- - auditoría de la reapertura con su motivo obligatorio.
--
-- La participación rechazada y su asistencia se conservan como historial.
-- La RPC queda disponible exclusivamente para service_role.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FUNCIÓN TRANSACCIONAL DE REAPERTURA
-- ============================================================

CREATE OR REPLACE FUNCTION public.reabrir_participacion_atomica(
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

    v_estado_pendiente_id uuid;
    v_nueva_participacion_id uuid;

    v_old_values jsonb;
    v_new_values jsonb;
    v_motivo text;
BEGIN
    -- --------------------------------------------------------
    -- NORMALIZAR MOTIVO
    -- --------------------------------------------------------

    v_motivo := btrim(COALESCE(p_motivo, ''));

    IF char_length(v_motivo) < 3
       OR char_length(v_motivo) > 1000 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_REASON'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
    -- --------------------------------------------------------
    -- FastAPI exige REASSIGN_ASSIGNMENT. Se repite en DB como
    -- defensa en profundidad porque esta función usa SECURITY DEFINER.
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

    IF v_actor.rol_codigo NOT IN (
        'SUPERADMIN',
        'DIRECTIVA',
        'COORDINADOR'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_ROLE'
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
    -- BLOQUEAR Y VALIDAR PARTICIPACIÓN RECHAZADA
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
            'error_code', 'PARTICIPANT_NOT_FOUND'
        );
    END IF;

    IF v_participacion.estado_codigo <> 'RECHAZADA' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_NOT_REJECTED'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR USUARIO Y TIPO DE PARTICIPACIÓN
    -- --------------------------------------------------------

    IF NOT EXISTS (
        SELECT 1
        FROM public.usuarios u
        JOIN public.roles r
            ON r.id = u.rol_id
        WHERE u.id = v_participacion.usuario_id
          AND u.activo = true
          AND u.deleted_at IS NULL
          AND r.codigo IN (
              'DIRECTIVA',
              'COORDINADOR',
              'MONITOR'
          )
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPANT_USER_NOT_AVAILABLE'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.tipos_participacion tp
        WHERE tp.id = v_participacion.tipo_participacion_id
          AND tp.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_TYPE_NOT_FOUND'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.asignacion_participantes ap
        WHERE ap.asignacion_id = p_asignacion_id
          AND ap.usuario_id = v_participacion.usuario_id
          AND ap.id <> p_participante_id
          AND ap.activo = true
          AND ap.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_ALREADY_PARTICIPATES'
        );
    END IF;

    SELECT ep.id
    INTO v_estado_pendiente_id
    FROM public.estados_participacion ep
    WHERE ep.codigo = 'PENDIENTE'
      AND ep.activo = true
    LIMIT 1;

    IF v_estado_pendiente_id IS NULL THEN
        RAISE EXCEPTION
            'No existe un estado de participación PENDIENTE activo.';
    END IF;


    -- --------------------------------------------------------
    -- PREPARAR AUDITORÍA
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


    -- --------------------------------------------------------
    -- ARCHIVAR PARTICIPACIÓN RECHAZADA
    -- --------------------------------------------------------

    UPDATE public.asignacion_participantes
    SET
        activo = false,
        deleted_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_participante_id
      AND activo = true
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPANT_NOT_FOUND'
        );
    END IF;


    -- --------------------------------------------------------
    -- CREAR NUEVA PARTICIPACIÓN PENDIENTE
    -- --------------------------------------------------------
    -- El trigger existente crea su asistencia PENDIENTE dentro
    -- de esta misma transacción.
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
        v_participacion.usuario_id,
        v_participacion.tipo_participacion_id,
        v_estado_pendiente_id,
        NULL,
        NULL,
        NULL,
        true,
        p_actor_user_id,
        p_actor_user_id
    )
    RETURNING id
    INTO v_nueva_participacion_id;

    v_new_values := jsonb_build_object(
        'id', v_nueva_participacion_id,
        'usuario_id', v_participacion.usuario_id,
        'tipo_participacion_id', v_participacion.tipo_participacion_id,
        'estado_participacion_id', v_estado_pendiente_id,
        'motivo_rechazo', NULL,
        'fecha_respuesta', NULL,
        'respondido_por', NULL,
        'activo', true
    );


    -- --------------------------------------------------------
    -- AUDITORÍA DE REAPERTURA
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
        'REOPEN_PARTICIPATION',
        'ASSIGNMENT_PARTICIPANT',
        v_nueva_participacion_id,
        v_old_values,
        v_new_values,
        'Participación rechazada reabierta. La participación anterior se conserva como historial y se creó una nueva participación PENDIENTE para que el usuario responda nuevamente. Motivo de reapertura: ' || v_motivo,
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'participante_anterior_id', p_participante_id,
        'nuevo_participante_id', v_nueva_participacion_id
    );
END;
$$;


COMMENT ON FUNCTION public.reabrir_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) IS
'Reabre de forma atómica una participación RECHAZADA: archiva la anterior, crea una nueva PENDIENTE para el mismo usuario y tipo, conserva la asistencia histórica y registra auditoría con motivo.';


-- ============================================================
-- 2. RESTRINGIR EJECUCIÓN DE LA RPC
-- ============================================================

REVOKE ALL ON FUNCTION public.reabrir_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reabrir_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.reabrir_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.reabrir_participacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;
