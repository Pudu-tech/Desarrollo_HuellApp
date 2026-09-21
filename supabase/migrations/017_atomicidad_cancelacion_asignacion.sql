-- ============================================================
-- HuellAPP
-- Migración 017
-- Cancelación atómica de asignaciones
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Evitar estados parciales al cancelar una asignación.
--
-- La función centraliza en una sola transacción PostgreSQL:
-- - cambio de estado a CANCELADA;
-- - historial_asignacion;
-- - audit_logs.
--
-- La RPC queda disponible exclusivamente para service_role,
-- porque FastAPI utiliza la clave secreta de Supabase y mantiene
-- la autorización RBAC en el backend.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FUNCIÓN TRANSACCIONAL DE CANCELACIÓN
-- ============================================================

CREATE OR REPLACE FUNCTION public.cancelar_asignacion_atomica(
    p_asignacion_id uuid,
    p_actor_user_id uuid,
    p_motivo text,
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
    v_estado_cancelada_id uuid;
    v_actor_role_id uuid;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR MOTIVO
    -- --------------------------------------------------------
    -- FastAPI ya valida este campo, pero la RPC mantiene su propia
    -- protección para no depender exclusivamente de la API.
    -- --------------------------------------------------------

    IF p_motivo IS NULL
       OR length(btrim(p_motivo)) < 3 THEN
        RAISE EXCEPTION
            'El motivo de cancelación debe contener al menos 3 caracteres.';
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ACTOR
    -- --------------------------------------------------------
    -- Se obtiene el rol real desde public.usuarios para registrar
    -- actor_role_id sin confiar en datos enviados por el frontend.
    -- --------------------------------------------------------

    SELECT u.rol_id
    INTO v_actor_role_id
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


    -- --------------------------------------------------------
    -- BLOQUEAR ASIGNACIÓN DURANTE LA OPERACIÓN
    -- --------------------------------------------------------
    -- FOR UPDATE evita que dos procesos modifiquen simultáneamente
    -- el mismo estado mientras se registra historial y auditoría.
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

    IF v_asignacion.estado_codigo NOT IN (
        'PENDIENTE',
        'CONFIRMADA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_STATE'
        );
    END IF;


    -- --------------------------------------------------------
    -- OBTENER ESTADO CANCELADA
    -- --------------------------------------------------------

    SELECT ea.id
    INTO v_estado_cancelada_id
    FROM public.estados_asignacion ea
    WHERE ea.codigo = 'CANCELADA'
      AND ea.activo = true
    LIMIT 1;

    IF v_estado_cancelada_id IS NULL THEN
        RAISE EXCEPTION
            'No existe un estado CANCELADA activo.';
    END IF;


    -- --------------------------------------------------------
    -- CAMBIAR ESTADO
    -- --------------------------------------------------------

    UPDATE public.asignaciones
    SET
        estado_id = v_estado_cancelada_id,
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
        'CANCEL_ASSIGNMENT',
        v_asignacion.estado_id,
        v_estado_cancelada_id,
        btrim(p_motivo),
        p_actor_user_id,
        'WEB'
    );


    -- --------------------------------------------------------
    -- REGISTRAR AUDITORÍA
    -- --------------------------------------------------------
    -- Esta escritura forma parte de la misma transacción. Si falla,
    -- PostgreSQL revierte también el UPDATE y el historial.
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
        v_actor_role_id,
        'CANCEL_ASSIGNMENT',
        'ASSIGNMENT',
        p_asignacion_id,
        jsonb_build_object(
            'estado_id', v_asignacion.estado_id,
            'estado', v_asignacion.estado_codigo
        ),
        jsonb_build_object(
            'estado_id', v_estado_cancelada_id,
            'estado', 'CANCELADA',
            'motivo', btrim(p_motivo)
        ),
        'Asignación cancelada. Motivo: ' || btrim(p_motivo),
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'estado_anterior_id', v_asignacion.estado_id,
        'estado_anterior', v_asignacion.estado_codigo,
        'estado_nuevo_id', v_estado_cancelada_id,
        'estado_nuevo', 'CANCELADA'
    );
END;
$$;


COMMENT ON FUNCTION public.cancelar_asignacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    inet,
    text
) IS
'Cancela una asignación PENDIENTE o CONFIRMADA de forma atómica y registra historial y auditoría en la misma transacción.';


-- ============================================================
-- 2. RESTRINGIR EJECUCIÓN DE LA RPC
-- ============================================================
-- El frontend no debe poder invocarla directamente.
-- Solo el backend, que utiliza service_role, obtiene EXECUTE.
-- ============================================================

REVOKE ALL ON FUNCTION public.cancelar_asignacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.cancelar_asignacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.cancelar_asignacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.cancelar_asignacion_atomica(
    uuid,
    uuid,
    text,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;
