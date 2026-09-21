-- ============================================================
-- HuellAPP
-- Migración 018
-- Reapertura atómica de asignaciones
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Evitar estados parciales al reabrir una asignación CANCELADA.
--
-- La función centraliza en una sola transacción PostgreSQL:
-- - validación del actor autorizado;
-- - recuperación de la cancelación más reciente;
-- - restauración del estado anterior;
-- - historial_asignacion;
-- - audit_logs.
--
-- La RPC queda disponible exclusivamente para service_role.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FUNCIÓN TRANSACCIONAL DE REAPERTURA
-- ============================================================

CREATE OR REPLACE FUNCTION public.reabrir_asignacion_atomica(
    p_asignacion_id uuid,
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
    v_asignacion record;
    v_actor record;
    v_cancelacion record;
    v_estado_restaurado_codigo varchar;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR ACTOR
    -- --------------------------------------------------------
    -- La reapertura tiene una regla más restrictiva que la
    -- cancelación: solo SUPERADMIN y DIRECTIVA pueden ejecutarla.
    -- La validación se repite en PostgreSQL para defensa en profundidad.
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
        'DIRECTIVA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_ROLE'
        );
    END IF;


    -- --------------------------------------------------------
    -- BLOQUEAR ASIGNACIÓN DURANTE LA OPERACIÓN
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
            'error_code', 'NOT_FOUND'
        );
    END IF;

    IF v_asignacion.activo IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INACTIVE'
        );
    END IF;

    IF v_asignacion.estado_codigo <> 'CANCELADA' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_STATE'
        );
    END IF;


    -- --------------------------------------------------------
    -- RECUPERAR ÚLTIMA CANCELACIÓN
    -- --------------------------------------------------------
    -- Se utiliza el estado anterior del último CANCEL_ASSIGNMENT.
    -- Solo PENDIENTE o CONFIRMADA son estados restaurables.
    -- --------------------------------------------------------

    SELECT
        h.id,
        h.estado_anterior_id,
        h.estado_nuevo_id,
        h.created_at
    INTO v_cancelacion
    FROM public.historial_asignacion h
    WHERE h.asignacion_id = p_asignacion_id
      AND h.accion = 'CANCEL_ASSIGNMENT'
    ORDER BY h.created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'CANCELLATION_HISTORY_NOT_FOUND'
        );
    END IF;

    -- La última cancelación debe haber terminado en el mismo estado
    -- CANCELADA que posee actualmente la asignación.
    IF v_cancelacion.estado_nuevo_id <> v_asignacion.estado_id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_CANCELLATION_HISTORY'
        );
    END IF;

    SELECT ea.codigo
    INTO v_estado_restaurado_codigo
    FROM public.estados_asignacion ea
    WHERE ea.id = v_cancelacion.estado_anterior_id;

    IF NOT FOUND
       OR v_estado_restaurado_codigo NOT IN (
            'PENDIENTE',
            'CONFIRMADA'
       ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_RESTORE_STATE'
        );
    END IF;


    -- --------------------------------------------------------
    -- RESTAURAR ESTADO
    -- --------------------------------------------------------

    UPDATE public.asignaciones
    SET
        estado_id = v_cancelacion.estado_anterior_id,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_asignacion_id;


    -- --------------------------------------------------------
    -- REGISTRAR HISTORIAL
    -- --------------------------------------------------------

    INSERT INTO public.historial_asignacion (
        asignacion_id,
        accion,
        estado_anterior_id,
        estado_nuevo_id,
        motivo,
        usuario_actor_id,
        origen
    )
    VALUES (
        p_asignacion_id,
        'REOPEN_ASSIGNMENT',
        v_asignacion.estado_id,
        v_cancelacion.estado_anterior_id,
        NULL,
        p_actor_user_id,
        'WEB'
    );


    -- --------------------------------------------------------
    -- REGISTRAR AUDITORÍA
    -- --------------------------------------------------------
    -- Si esta inserción falla, PostgreSQL revierte también el UPDATE
    -- y el historial porque toda la función corre en una transacción.
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
        'REOPEN_ASSIGNMENT',
        'ASSIGNMENT',
        p_asignacion_id,
        jsonb_build_object(
            'estado_id', v_asignacion.estado_id,
            'estado', 'CANCELADA'
        ),
        jsonb_build_object(
            'estado_id', v_cancelacion.estado_anterior_id,
            'estado', v_estado_restaurado_codigo
        ),
        'Asignación reabierta y restaurada al estado '
            || v_estado_restaurado_codigo || '.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'estado_anterior_id', v_asignacion.estado_id,
        'estado_anterior', 'CANCELADA',
        'estado_nuevo_id', v_cancelacion.estado_anterior_id,
        'estado_nuevo', v_estado_restaurado_codigo
    );
END;
$$;


COMMENT ON FUNCTION public.reabrir_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    inet,
    text
) IS
'Reabre una asignación CANCELADA de forma atómica, restaura el estado previo a la cancelación más reciente y registra historial y auditoría en la misma transacción.';


-- ============================================================
-- 2. RESTRINGIR EJECUCIÓN DE LA RPC
-- ============================================================

REVOKE ALL ON FUNCTION public.reabrir_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reabrir_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.reabrir_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.reabrir_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;
