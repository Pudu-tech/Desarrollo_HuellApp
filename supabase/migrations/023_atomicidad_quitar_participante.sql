-- ============================================================
-- HuellAPP
-- Migración 023
-- Eliminación lógica atómica de participante
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Evitar estados parciales al quitar un participante de una asignación.
--
-- La operación se ejecuta en una sola transacción PostgreSQL:
-- - valida actor, permiso, asignación y participación;
-- - archiva la participación mediante soft-delete;
-- - conserva la asistencia y el historial asociado;
-- - si se quitó el último RELATOR ACEPTADO de una asignación CONFIRMADA,
--   cambia la asignación a PENDIENTE;
-- - registra la auditoría de la eliminación lógica;
-- - registra la auditoría del cambio global de estado, si corresponde.
--
-- Si cualquier escritura falla, PostgreSQL revierte toda la operación.
-- La RPC queda disponible exclusivamente para service_role.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FUNCIÓN TRANSACCIONAL
-- ============================================================

CREATE OR REPLACE FUNCTION public.quitar_participante_atomico(
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

    v_estado_pendiente_asignacion_id uuid;

    v_era_relator_aceptado boolean := false;
    v_quedan_relatores_aceptados boolean := false;
    v_asignacion_volvio_pendiente boolean := false;

    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
    -- --------------------------------------------------------
    -- FastAPI también exige REASSIGN_ASSIGNMENT. La validación se
    -- repite en PostgreSQL porque esta función usa SECURITY DEFINER.
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

    v_era_relator_aceptado := (
        v_participacion.tipo_codigo = 'RELATOR'
        AND v_participacion.estado_codigo = 'ACEPTADA'
    );

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
    -- ARCHIVAR PARTICIPACIÓN
    -- --------------------------------------------------------
    -- No se elimina físicamente. La asistencia asociada tampoco se
    -- modifica, por lo que permanece disponible como historial.
    -- --------------------------------------------------------

    UPDATE public.asignacion_participantes
    SET
        activo = false,
        deleted_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_participante_id
      AND asignacion_id = p_asignacion_id
      AND activo = true
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPANT_CHANGED'
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
        'REMOVE_PARTICIPANT',
        'ASSIGNMENT_PARTICIPANT',
        p_participante_id,
        v_old_values,
        v_new_values,
        'Participante archivado de la asignación. Se conserva su historial y asistencia.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    -- --------------------------------------------------------
    -- CONFIRMADA -> PENDIENTE SI SE QUITÓ EL ÚLTIMO RELATOR ACEPTADO
    -- --------------------------------------------------------

    IF v_era_relator_aceptado
       AND v_asignacion.estado_codigo = 'CONFIRMADA' THEN

        SELECT EXISTS (
            SELECT 1
            FROM public.asignacion_participantes ap
            JOIN public.tipos_participacion tp
                ON tp.id = ap.tipo_participacion_id
            JOIN public.estados_participacion ep
                ON ep.id = ap.estado_participacion_id
            WHERE ap.asignacion_id = p_asignacion_id
              AND ap.activo = true
              AND ap.deleted_at IS NULL
              AND tp.codigo = 'RELATOR'
              AND ep.codigo = 'ACEPTADA'
        )
        INTO v_quedan_relatores_aceptados;

        IF NOT v_quedan_relatores_aceptados THEN
            SELECT ea.id
            INTO v_estado_pendiente_asignacion_id
            FROM public.estados_asignacion ea
            WHERE ea.codigo = 'PENDIENTE'
              AND ea.activo = true
            LIMIT 1;

            IF v_estado_pendiente_asignacion_id IS NULL THEN
                RAISE EXCEPTION
                    'No existe un estado de asignación PENDIENTE activo.';
            END IF;

            UPDATE public.asignaciones
            SET
                estado_id = v_estado_pendiente_asignacion_id,
                updated_by = p_actor_user_id,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = p_asignacion_id
              AND estado_id = v_asignacion.estado_id
              AND activo = true
              AND deleted_at IS NULL;

            IF FOUND THEN
                v_asignacion_volvio_pendiente := true;

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
                    'UNCONFIRM_ASSIGNMENT',
                    'ASSIGNMENT',
                    p_asignacion_id,
                    jsonb_build_object(
                        'estado', 'CONFIRMADA',
                        'estado_id', v_asignacion.estado_id
                    ),
                    jsonb_build_object(
                        'estado', 'PENDIENTE',
                        'estado_id', v_estado_pendiente_asignacion_id
                    ),
                    'La asignación volvió a PENDIENTE porque dejó de tener un RELATOR ACEPTADO activo.',
                    p_request_id,
                    p_ip_address,
                    p_user_agent,
                    'WEB'
                );
            END IF;
        END IF;
    END IF;


    RETURN jsonb_build_object(
        'ok', true,
        'participante_id', p_participante_id,
        'asignacion_volvio_pendiente', v_asignacion_volvio_pendiente
    );
END;
$$;


COMMENT ON FUNCTION public.quitar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) IS
'Archiva un participante de forma atómica, conserva su historial y revierte CONFIRMADA a PENDIENTE si se elimina el último RELATOR ACEPTADO activo.';


-- ============================================================
-- 2. RESTRINGIR EJECUCIÓN DE LA RPC
-- ============================================================

REVOKE ALL ON FUNCTION public.quitar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.quitar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.quitar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.quitar_participante_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;