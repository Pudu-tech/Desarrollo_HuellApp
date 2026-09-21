-- ============================================================
-- HuellAPP
-- Migración 021
-- Cambio atómico de tipo de participación
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Evitar estados parciales al cambiar el tipo de participación.
--
-- Reglas:
-- - Si la participación está PENDIENTE, se actualiza el tipo en el mismo
--   registro porque todavía no existe una respuesta del participante.
-- - Si está ACEPTADA o RECHAZADA, el registro anterior se archiva y se crea
--   una nueva participación PENDIENTE para preservar la trazabilidad.
-- - Si se reemplaza un RELATOR ACEPTADO y ya no queda otro RELATOR ACEPTADO
--   activo, la asignación vuelve de CONFIRMADA a PENDIENTE.
-- - La asistencia histórica del registro archivado no se elimina. Cuando se
--   crea una nueva participación, el trigger existente crea su asistencia
--   PENDIENTE dentro de esta misma transacción.
-- - Todos los cambios críticos quedan registrados en audit_logs.
--
-- La RPC queda disponible exclusivamente para service_role.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FUNCIÓN TRANSACCIONAL
-- ============================================================

CREATE OR REPLACE FUNCTION public.cambiar_tipo_participacion_atomico(
    p_asignacion_id uuid,
    p_participante_id uuid,
    p_nuevo_tipo_participacion_id uuid,
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
    v_nuevo_tipo record;

    v_estado_pendiente_participacion_id uuid;
    v_estado_pendiente_asignacion_id uuid;
    v_participante_resultado_id uuid;

    v_creo_nueva_participacion boolean := false;
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
    -- repite en PostgreSQL porque la función usa SECURITY DEFINER.
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
    -- BLOQUEAR Y VALIDAR PARTICIPACIÓN ACTUAL
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

    IF v_participacion.estado_codigo NOT IN (
        'PENDIENTE',
        'ACEPTADA',
        'RECHAZADA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_PARTICIPATION_STATE'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR USUARIO DE LA PARTICIPACIÓN
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


    -- --------------------------------------------------------
    -- VALIDAR NUEVO TIPO DE PARTICIPACIÓN
    -- --------------------------------------------------------

    SELECT
        tp.id,
        tp.codigo
    INTO v_nuevo_tipo
    FROM public.tipos_participacion tp
    WHERE tp.id = p_nuevo_tipo_participacion_id
      AND tp.activo = true
      AND tp.codigo IN (
          'RELATOR',
          'ACOMPANAMIENTO',
          'OBSERVADOR'
      );

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_TYPE_NOT_FOUND'
        );
    END IF;

    IF v_participacion.tipo_participacion_id = p_nuevo_tipo_participacion_id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'SAME_PARTICIPATION_TYPE'
        );
    END IF;


    -- --------------------------------------------------------
    -- PREPARAR DATOS PARA AUDITORÍA
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

    v_era_relator_aceptado := (
        v_participacion.tipo_codigo = 'RELATOR'
        AND v_participacion.estado_codigo = 'ACEPTADA'
    );


    -- --------------------------------------------------------
    -- CASO 1: PARTICIPACIÓN PENDIENTE
    -- --------------------------------------------------------
    -- Como aún no existe respuesta, el tipo se modifica sobre el
    -- mismo registro. La asistencia asociada permanece intacta.
    -- --------------------------------------------------------

    IF v_participacion.estado_codigo = 'PENDIENTE' THEN
        UPDATE public.asignacion_participantes
        SET
            tipo_participacion_id = p_nuevo_tipo_participacion_id,
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

        v_participante_resultado_id := p_participante_id;

        v_new_values := jsonb_build_object(
            'id', p_participante_id,
            'usuario_id', v_participacion.usuario_id,
            'tipo_participacion_id', p_nuevo_tipo_participacion_id,
            'estado_participacion_id', v_participacion.estado_participacion_id,
            'motivo_rechazo', v_participacion.motivo_rechazo,
            'fecha_respuesta', v_participacion.fecha_respuesta,
            'respondido_por', v_participacion.respondido_por,
            'activo', true
        );

    ELSE
        -- ----------------------------------------------------
        -- CASO 2: PARTICIPACIÓN YA RESPONDIDA
        -- ----------------------------------------------------
        -- ACEPTADA o RECHAZADA se conserva como historial. Se crea
        -- una nueva PENDIENTE para que el usuario responda nuevamente.
        -- ----------------------------------------------------

        SELECT ep.id
        INTO v_estado_pendiente_participacion_id
        FROM public.estados_participacion ep
        WHERE ep.codigo = 'PENDIENTE'
          AND ep.activo = true
        LIMIT 1;

        IF v_estado_pendiente_participacion_id IS NULL THEN
            RAISE EXCEPTION
                'No existe un estado de participación PENDIENTE activo.';
        END IF;

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
            p_nuevo_tipo_participacion_id,
            v_estado_pendiente_participacion_id,
            NULL,
            NULL,
            NULL,
            true,
            p_actor_user_id,
            p_actor_user_id
        )
        RETURNING id
        INTO v_participante_resultado_id;

        v_creo_nueva_participacion := true;

        v_new_values := jsonb_build_object(
            'id', v_participante_resultado_id,
            'usuario_id', v_participacion.usuario_id,
            'tipo_participacion_id', p_nuevo_tipo_participacion_id,
            'estado_participacion_id', v_estado_pendiente_participacion_id,
            'motivo_rechazo', NULL,
            'fecha_respuesta', NULL,
            'respondido_por', NULL,
            'activo', true
        );
    END IF;


    -- --------------------------------------------------------
    -- AUDITORÍA DEL CAMBIO DE TIPO
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
        'UPDATE_PARTICIPANT_TYPE',
        'ASSIGNMENT_PARTICIPANT',
        v_participante_resultado_id,
        v_old_values,
        v_new_values,
        CASE
            WHEN v_creo_nueva_participacion THEN
                'Tipo de participación actualizado. La participación respondida se conservó como historial y se creó una nueva participación PENDIENTE para solicitar una nueva respuesta.'
            ELSE
                'Tipo de participación actualizado sobre una participación PENDIENTE.'
        END,
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    -- --------------------------------------------------------
    -- CONFIRMADA -> PENDIENTE SI SE RETIRÓ EL ÚLTIMO RELATOR ACEPTADO
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
              AND estado_id = v_asignacion.estado_id;

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
        'participante_anterior_id', p_participante_id,
        'participante_resultado_id', v_participante_resultado_id,
        'creo_nueva_participacion', v_creo_nueva_participacion,
        'asignacion_volvio_pendiente', v_asignacion_volvio_pendiente
    );
END;
$$;


COMMENT ON FUNCTION public.cambiar_tipo_participacion_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) IS
'Cambia el tipo de participación de forma atómica. Actualiza en sitio si está PENDIENTE o conserva la participación respondida como historial y crea una nueva PENDIENTE; además ajusta CONFIRMADA a PENDIENTE si desaparece el último RELATOR ACEPTADO.';


-- ============================================================
-- 2. RESTRINGIR EJECUCIÓN DE LA RPC
-- ============================================================

REVOKE ALL ON FUNCTION public.cambiar_tipo_participacion_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.cambiar_tipo_participacion_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.cambiar_tipo_participacion_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.cambiar_tipo_participacion_atomico(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;
