-- ============================================================
-- HuellAPP
-- Migración 028
-- Creación atómica de asignación
-- ============================================================
--
-- Crea dentro de una sola transacción:
-- - asignación;
-- - participantes PENDIENTES;
-- - asistencias PENDIENTES mediante trigger;
-- - contactos;
-- - auditoría CREATE_ASSIGNMENT.
--
-- Si cualquier escritura falla, PostgreSQL revierte todo.
-- ============================================================

BEGIN;


CREATE OR REPLACE FUNCTION public.crear_asignacion_atomica(
    p_tipo_actividad_id uuid,
    p_colegio_id uuid,
    p_curso_colegio_id uuid,
    p_sala_id uuid,
    p_ramo_id uuid,
    p_espacio_reflexion_id uuid,
    p_espacio_encuentro_id uuid,
    p_fecha date,
    p_hora_inicio time,
    p_hora_fin time,
    p_lugar text,
    p_observacion text,
    p_participantes jsonb,
    p_contactos jsonb,
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

    v_estado_asignacion_id uuid;
    v_estado_participacion_id uuid;

    v_asignacion_id uuid;

    v_participante jsonb;
    v_contacto jsonb;

    v_participantes_auditoria jsonb;
    v_contactos_auditoria jsonb;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- VALIDAR ACTOR
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


    -- --------------------------------------------------------
    -- VALIDAR PERMISO
    -- --------------------------------------------------------

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
            ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'CREATE_ASSIGNMENT'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR PARTICIPANTES
    -- --------------------------------------------------------

    IF p_participantes IS NULL
       OR jsonb_typeof(p_participantes) <> 'array'
       OR jsonb_array_length(p_participantes) = 0 THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_PARTICIPANTS'
        );

    END IF;

    IF p_contactos IS NULL THEN
        p_contactos := '[]'::jsonb;
    END IF;

    IF jsonb_typeof(p_contactos) <> 'array' THEN
        RAISE EXCEPTION
            'p_contactos debe ser un arreglo JSON';
    END IF;


    -- --------------------------------------------------------
    -- ESTADO INICIAL DE ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT ea.id
    INTO v_estado_asignacion_id
    FROM public.estados_asignacion ea
    WHERE ea.codigo = 'PENDIENTE'
      AND ea.activo = true
    LIMIT 1;

    IF v_estado_asignacion_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code',
            'PENDING_ASSIGNMENT_STATE_NOT_FOUND'
        );
    END IF;


    -- --------------------------------------------------------
    -- ESTADO INICIAL DE PARTICIPACIONES
    -- --------------------------------------------------------

    SELECT ep.id
    INTO v_estado_participacion_id
    FROM public.estados_participacion ep
    WHERE ep.codigo = 'PENDIENTE'
      AND ep.activo = true
    LIMIT 1;

    IF v_estado_participacion_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code',
            'PENDING_PARTICIPATION_STATE_NOT_FOUND'
        );
    END IF;


    -- --------------------------------------------------------
    -- CREAR ASIGNACIÓN
    -- --------------------------------------------------------

    INSERT INTO public.asignaciones (
        tipo_actividad_id,
        colegio_id,
        curso_colegio_id,
        sala_id,
        ramo_id,
        espacio_reflexion_id,
        espacio_encuentro_id,
        fecha,
        hora_inicio,
        hora_fin,
        lugar,
        observacion,
        estado_id,
        activo,
        created_by,
        updated_by
    )
    VALUES (
        p_tipo_actividad_id,
        p_colegio_id,
        p_curso_colegio_id,
        p_sala_id,
        p_ramo_id,
        p_espacio_reflexion_id,
        p_espacio_encuentro_id,
        p_fecha,
        p_hora_inicio,
        p_hora_fin,
        p_lugar,
        p_observacion,
        v_estado_asignacion_id,
        true,
        p_actor_user_id,
        p_actor_user_id
    )
    RETURNING id
    INTO v_asignacion_id;


    -- --------------------------------------------------------
    -- CREAR PARTICIPANTES
    -- --------------------------------------------------------
    --
    -- El trigger existente crea automáticamente una asistencia
    -- PENDIENTE por cada participación creada.
    -- --------------------------------------------------------

    FOR v_participante IN
        SELECT value
        FROM jsonb_array_elements(p_participantes)
    LOOP
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
            v_asignacion_id,
            (
                v_participante ->> 'usuario_id'
            )::uuid,
            (
                v_participante ->>
                'tipo_participacion_id'
            )::uuid,
            v_estado_participacion_id,
            NULL,
            NULL,
            NULL,
            true,
            p_actor_user_id,
            p_actor_user_id
        );
    END LOOP;


    -- --------------------------------------------------------
    -- CREAR CONTACTOS
    -- --------------------------------------------------------

    FOR v_contacto IN
        SELECT value
        FROM jsonb_array_elements(p_contactos)
    LOOP
        INSERT INTO public.asignacion_contactos (
            asignacion_id,
            contacto_colegio_id,
            created_by
        )
        VALUES (
            v_asignacion_id,
            (
                v_contacto ->>
                'contacto_colegio_id'
            )::uuid,
            p_actor_user_id
        );
    END LOOP;


    -- --------------------------------------------------------
    -- CONSTRUIR PARTICIPANTES PARA AUDITORÍA
    -- --------------------------------------------------------

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id',
                    ap.id,
                'usuario_id',
                    ap.usuario_id,
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
            ORDER BY ap.created_at, ap.id
        ),
        '[]'::jsonb
    )
    INTO v_participantes_auditoria
    FROM public.asignacion_participantes ap
    WHERE ap.asignacion_id = v_asignacion_id
      AND ap.activo = true
      AND ap.deleted_at IS NULL;


    -- --------------------------------------------------------
    -- CONSTRUIR CONTACTOS PARA AUDITORÍA
    -- --------------------------------------------------------

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id',
                    ac.id,
                'contacto_colegio_id',
                    ac.contacto_colegio_id
            )
            ORDER BY ac.id
        ),
        '[]'::jsonb
    )
    INTO v_contactos_auditoria
    FROM public.asignacion_contactos ac
    WHERE ac.asignacion_id = v_asignacion_id;


    -- --------------------------------------------------------
    -- CONSTRUIR SNAPSHOT DE ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT jsonb_build_object(
        'id',
            a.id,
        'tipo_actividad_id',
            a.tipo_actividad_id,
        'colegio_id',
            a.colegio_id,
        'curso_colegio_id',
            a.curso_colegio_id,
        'sala_id',
            a.sala_id,
        'ramo_id',
            a.ramo_id,
        'espacio_reflexion_id',
            a.espacio_reflexion_id,
        'espacio_encuentro_id',
            a.espacio_encuentro_id,
        'fecha',
            a.fecha,
        'hora_inicio',
            a.hora_inicio,
        'hora_fin',
            a.hora_fin,
        'lugar',
            a.lugar,
        'observacion',
            a.observacion,
        'estado_id',
            a.estado_id,
        'activo',
            a.activo,
        'created_at',
            a.created_at,
        'updated_at',
            a.updated_at,
        'participantes',
            v_participantes_auditoria,
        'contactos',
            v_contactos_auditoria
    )
    INTO v_new_values
    FROM public.asignaciones a
    WHERE a.id = v_asignacion_id;


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
        'CREATE_ASSIGNMENT',
        'ASSIGNMENT',
        v_asignacion_id,
        NULL,
        v_new_values,
        'Creación de asignación.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'asignacion_id', v_asignacion_id
    );
END;
$$;


COMMENT ON FUNCTION public.crear_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    date,
    time,
    time,
    text,
    text,
    jsonb,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) IS
'Crea asignación, participantes, asistencias automáticas, contactos y auditoría dentro de una única transacción.';


-- ============================================================
-- SEGURIDAD
-- ============================================================

REVOKE ALL ON FUNCTION public.crear_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    date,
    time,
    time,
    text,
    text,
    jsonb,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.crear_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    date,
    time,
    time,
    text,
    text,
    jsonb,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.crear_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    date,
    time,
    time,
    text,
    text,
    jsonb,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.crear_asignacion_atomica(
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    uuid,
    date,
    time,
    time,
    text,
    text,
    jsonb,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;