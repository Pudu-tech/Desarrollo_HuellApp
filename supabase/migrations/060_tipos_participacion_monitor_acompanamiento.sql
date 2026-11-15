-- HuellApp · tipos de participación vigentes.
--
-- Desde esta versión, las nuevas participaciones usan únicamente:
--   - MONITOR
--   - ACOMPANAMIENTO
--
-- RELATOR y OBSERVADOR se conservan como catálogo histórico inactivo.
-- Las RPC que dependen del participante principal consideran tanto MONITOR
-- como RELATOR para que registros históricos continúen funcionando.

BEGIN;

INSERT INTO public.tipos_participacion (codigo, nombre, descripcion, activo)
VALUES (
    'MONITOR',
    'Monitor',
    'Participante principal que ejecuta la actividad.',
    true
)
ON CONFLICT (codigo) DO UPDATE
SET nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    activo = true,
    updated_at = CURRENT_TIMESTAMP;

UPDATE public.tipos_participacion
SET activo = CASE
        WHEN codigo IN ('MONITOR', 'ACOMPANAMIENTO') THEN true
        ELSE false
    END,
    updated_at = CURRENT_TIMESTAMP
WHERE codigo IN ('MONITOR', 'ACOMPANAMIENTO', 'RELATOR', 'OBSERVADOR');

CREATE OR REPLACE FUNCTION public.reasignar_participante_atomico(
    p_asignacion_id uuid,
    p_participante_id uuid,
    p_nuevo_usuario_id uuid,
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
    v_nuevo_usuario record;

    v_estado_pendiente_participacion_id uuid;
    v_estado_pendiente_asignacion_id uuid;

    v_nueva_participacion_id uuid;

    v_era_relator_aceptado boolean := false;
    v_quedan_relatores_aceptados boolean := false;
    v_asignacion_volvio_pendiente boolean := false;

    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
    -- --------------------------------------------------------
    -- FastAPI ya exige REASSIGN_ASSIGNMENT. Esta validación se
    -- repite en PostgreSQL como defensa en profundidad porque la
    -- función usa SECURITY DEFINER.
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
    -- BLOQUEAR ASIGNACIÓN DURANTE TODA LA OPERACIÓN
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

    IF v_participacion.usuario_id = p_nuevo_usuario_id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'SAME_USER'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR NUEVO USUARIO
    -- --------------------------------------------------------

    SELECT
        u.id,
        r.codigo AS rol_codigo
    INTO v_nuevo_usuario
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_nuevo_usuario_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NEW_USER_NOT_FOUND'
        );
    END IF;

    IF v_nuevo_usuario.rol_codigo NOT IN (
        'DIRECTIVA',
        'COORDINADOR',
        'MONITOR'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NEW_USER_CANNOT_PARTICIPATE'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.asignacion_participantes ap
        WHERE ap.asignacion_id = p_asignacion_id
          AND ap.usuario_id = p_nuevo_usuario_id
          AND ap.activo = true
          AND ap.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NEW_USER_ALREADY_PARTICIPATES'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR TIPO Y ESTADO PENDIENTE
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- PREPARAR AUDITORÍA DEL REGISTRO ANTERIOR
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
        v_participacion.tipo_codigo IN ('RELATOR', 'MONITOR')
        AND v_participacion.estado_codigo = 'ACEPTADA'
    );


    -- --------------------------------------------------------
    -- ARCHIVAR PARTICIPACIÓN ANTERIOR
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
    -- El trigger trg_create_pending_attendance crea su asistencia
    -- PENDIENTE dentro de esta misma transacción.
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
        p_nuevo_usuario_id,
        v_participacion.tipo_participacion_id,
        v_estado_pendiente_participacion_id,
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
        'usuario_id', p_nuevo_usuario_id,
        'tipo_participacion_id', v_participacion.tipo_participacion_id,
        'estado_participacion_id', v_estado_pendiente_participacion_id,
        'motivo_rechazo', NULL,
        'fecha_respuesta', NULL,
        'respondido_por', NULL,
        'activo', true
    );


    -- --------------------------------------------------------
    -- AUDITORÍA DE REASIGNACIÓN
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
        'REASSIGN_PARTICIPANT',
        'ASSIGNMENT_PARTICIPANT',
        v_nueva_participacion_id,
        v_old_values,
        v_new_values,
        'Participación reasignada a otro usuario. La participación anterior y su asistencia permanecen como historial.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    -- --------------------------------------------------------
    -- CONFIRMADA -> PENDIENTE SI YA NO HAY PARTICIPANTE PRINCIPAL ACEPTADO
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
              AND tp.codigo IN ('RELATOR', 'MONITOR')
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
                    'La asignación volvió a PENDIENTE porque dejó de tener un participante principal aceptado activo.',
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
        'nuevo_participante_id', v_nueva_participacion_id,
        'asignacion_volvio_pendiente', v_asignacion_volvio_pendiente
    );
END;
$$;

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
          'MONITOR',
          'ACOMPANAMIENTO'
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
        v_participacion.tipo_codigo IN ('RELATOR', 'MONITOR')
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
    -- CONFIRMADA -> PENDIENTE SI SE RETIRÓ EL ÚLTIMO PARTICIPANTE PRINCIPAL ACEPTADO
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
              AND tp.codigo IN ('RELATOR', 'MONITOR')
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
                    'La asignación volvió a PENDIENTE porque dejó de tener un participante principal aceptado activo.',
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
        v_participacion.tipo_codigo IN ('RELATOR', 'MONITOR')
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
    -- CONFIRMADA -> PENDIENTE SI SE QUITÓ EL ÚLTIMO PARTICIPANTE PRINCIPAL ACEPTADO
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
              AND tp.codigo IN ('RELATOR', 'MONITOR')
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
                    'La asignación volvió a PENDIENTE porque dejó de tener un participante principal aceptado activo.',
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
    -- PENDIENTE -> CONFIRMADA SI ACEPTÓ UN PARTICIPANTE PRINCIPAL
    -- --------------------------------------------------------

    IF v_participacion.tipo_codigo IN ('RELATOR', 'MONITOR')
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
                'Asignación confirmada automáticamente por aceptación de un participante principal.',
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

COMMIT;
