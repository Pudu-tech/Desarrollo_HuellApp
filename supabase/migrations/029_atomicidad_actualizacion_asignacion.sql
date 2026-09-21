-- ============================================================
-- HuellAPP
-- Migración 029
-- Actualización atómica de asignación
-- ============================================================
--
-- Ejecuta en una sola transacción:
-- - actualización parcial de la asignación;
-- - reemplazo de contactos, solo cuando vienen en el PATCH;
-- - auditoría UPDATE_ASSIGNMENT.
--
-- Incluye control optimista mediante updated_at para evitar
-- sobreescribir cambios concurrentes.
-- ============================================================

BEGIN;


CREATE OR REPLACE FUNCTION public.actualizar_asignacion_atomica(
    p_asignacion_id uuid,
    p_cambios jsonb,
    p_reemplazar_contactos boolean,
    p_contactos jsonb,
    p_expected_updated_at timestamptz,
    p_campos_modificados text[],
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
    v_contacto jsonb;

    v_participantes_old jsonb;
    v_contactos_old jsonb;
    v_old_values jsonb;

    v_participantes_new jsonb;
    v_contactos_new jsonb;
    v_new_values jsonb;
BEGIN
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
          AND p.codigo = 'UPDATE_ASSIGNMENT'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;


    -- --------------------------------------------------------
    -- BLOQUEAR ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT
        a.*,
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

    -- Se replica la regla actual del backend:
    -- CANCELADA y NO_REALIZADA no admiten PATCH normal.
    IF v_asignacion.estado_codigo IN (
        'CANCELADA',
        'NO_REALIZADA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CLOSED'
        );
    END IF;


    -- --------------------------------------------------------
    -- CONTROL DE CONCURRENCIA
    -- --------------------------------------------------------

    IF v_asignacion.updated_at IS DISTINCT FROM
       p_expected_updated_at THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CHANGED'
        );
    END IF;


    -- --------------------------------------------------------
    -- SNAPSHOT ANTERIOR - PARTICIPANTES
    -- --------------------------------------------------------

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
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
            ORDER BY ap.created_at, ap.id
        ),
        '[]'::jsonb
    )
    INTO v_participantes_old
    FROM public.asignacion_participantes ap
    WHERE ap.asignacion_id = p_asignacion_id
      AND ap.activo = true
      AND ap.deleted_at IS NULL;


    -- --------------------------------------------------------
    -- SNAPSHOT ANTERIOR - CONTACTOS
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
    INTO v_contactos_old
    FROM public.asignacion_contactos ac
    WHERE ac.asignacion_id = p_asignacion_id;


    v_old_values := jsonb_build_object(
        'id',
            v_asignacion.id,
        'tipo_actividad_id',
            v_asignacion.tipo_actividad_id,
        'colegio_id',
            v_asignacion.colegio_id,
        'curso_colegio_id',
            v_asignacion.curso_colegio_id,
        'sala_id',
            v_asignacion.sala_id,
        'ramo_id',
            v_asignacion.ramo_id,
        'espacio_reflexion_id',
            v_asignacion.espacio_reflexion_id,
        'espacio_encuentro_id',
            v_asignacion.espacio_encuentro_id,
        'fecha',
            v_asignacion.fecha,
        'hora_inicio',
            v_asignacion.hora_inicio,
        'hora_fin',
            v_asignacion.hora_fin,
        'lugar',
            v_asignacion.lugar,
        'observacion',
            v_asignacion.observacion,
        'estado_id',
            v_asignacion.estado_id,
        'activo',
            v_asignacion.activo,
        'created_at',
            v_asignacion.created_at,
        'updated_at',
            v_asignacion.updated_at,
        'participantes',
            v_participantes_old,
        'contactos',
            v_contactos_old
    );


    -- --------------------------------------------------------
    -- ACTUALIZACIÓN PARCIAL
    -- --------------------------------------------------------
    -- La existencia de la clave indica que el campo fue enviado.
    -- JSON null significa limpiar el valor.
    -- --------------------------------------------------------

    UPDATE public.asignaciones
    SET
        colegio_id = CASE
            WHEN p_cambios ? 'colegio_id'
                THEN (p_cambios ->> 'colegio_id')::uuid
            ELSE colegio_id
        END,

        curso_colegio_id = CASE
            WHEN p_cambios ? 'curso_colegio_id'
                THEN (p_cambios ->> 'curso_colegio_id')::uuid
            ELSE curso_colegio_id
        END,

        sala_id = CASE
            WHEN p_cambios ? 'sala_id'
                THEN (p_cambios ->> 'sala_id')::uuid
            ELSE sala_id
        END,

        ramo_id = CASE
            WHEN p_cambios ? 'ramo_id'
                THEN (p_cambios ->> 'ramo_id')::uuid
            ELSE ramo_id
        END,

        espacio_reflexion_id = CASE
            WHEN p_cambios ? 'espacio_reflexion_id'
                THEN (
                    p_cambios ->> 'espacio_reflexion_id'
                )::uuid
            ELSE espacio_reflexion_id
        END,

        espacio_encuentro_id = CASE
            WHEN p_cambios ? 'espacio_encuentro_id'
                THEN (
                    p_cambios ->> 'espacio_encuentro_id'
                )::uuid
            ELSE espacio_encuentro_id
        END,

        fecha = CASE
            WHEN p_cambios ? 'fecha'
                THEN (p_cambios ->> 'fecha')::date
            ELSE fecha
        END,

        hora_inicio = CASE
            WHEN p_cambios ? 'hora_inicio'
                THEN (p_cambios ->> 'hora_inicio')::time
            ELSE hora_inicio
        END,

        hora_fin = CASE
            WHEN p_cambios ? 'hora_fin'
                THEN (p_cambios ->> 'hora_fin')::time
            ELSE hora_fin
        END,

        lugar = CASE
            WHEN p_cambios ? 'lugar'
                THEN p_cambios ->> 'lugar'
            ELSE lugar
        END,

        observacion = CASE
            WHEN p_cambios ? 'observacion'
                THEN p_cambios ->> 'observacion'
            ELSE observacion
        END,

        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP

    WHERE id = p_asignacion_id
      AND updated_at = p_expected_updated_at
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CHANGED'
        );
    END IF;


    -- --------------------------------------------------------
    -- REEMPLAZAR CONTACTOS
    -- --------------------------------------------------------

    IF p_reemplazar_contactos IS TRUE THEN

        IF p_contactos IS NULL
           OR jsonb_typeof(p_contactos) <> 'array' THEN
            RAISE EXCEPTION
                'p_contactos debe ser un arreglo JSON';
        END IF;

        DELETE FROM public.asignacion_contactos
        WHERE asignacion_id = p_asignacion_id;

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
                p_asignacion_id,
                (
                    v_contacto ->>
                    'contacto_colegio_id'
                )::uuid,
                p_actor_user_id
            );
        END LOOP;

    END IF;


    -- --------------------------------------------------------
    -- SNAPSHOT NUEVO - PARTICIPANTES
    -- --------------------------------------------------------

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
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
            ORDER BY ap.created_at, ap.id
        ),
        '[]'::jsonb
    )
    INTO v_participantes_new
    FROM public.asignacion_participantes ap
    WHERE ap.asignacion_id = p_asignacion_id
      AND ap.activo = true
      AND ap.deleted_at IS NULL;


    -- --------------------------------------------------------
    -- SNAPSHOT NUEVO - CONTACTOS
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
    INTO v_contactos_new
    FROM public.asignacion_contactos ac
    WHERE ac.asignacion_id = p_asignacion_id;


    -- --------------------------------------------------------
    -- SNAPSHOT NUEVO - ASIGNACIÓN
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
            v_participantes_new,
        'contactos',
            v_contactos_new
    )
    INTO v_new_values
    FROM public.asignaciones a
    WHERE a.id = p_asignacion_id;


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
        'UPDATE_ASSIGNMENT',
        'ASSIGNMENT',
        p_asignacion_id,
        v_old_values,
        v_new_values,
        (
            'Actualización de asignación. Campos enviados: '
            || array_to_string(
                p_campos_modificados,
                ', '
            )
            || '.'
        ),
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'asignacion_id', p_asignacion_id
    );
END;
$$;


COMMENT ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,
    jsonb,
    boolean,
    jsonb,
    timestamptz,
    text[],
    uuid,
    uuid,
    inet,
    text
) IS
'Actualiza asignación y contactos de forma atómica, con control optimista de concurrencia y auditoría.';


-- ============================================================
-- SEGURIDAD
-- ============================================================

REVOKE ALL ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,
    jsonb,
    boolean,
    jsonb,
    timestamptz,
    text[],
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,
    jsonb,
    boolean,
    jsonb,
    timestamptz,
    text[],
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,
    jsonb,
    boolean,
    jsonb,
    timestamptz,
    text[],
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,
    jsonb,
    boolean,
    jsonb,
    timestamptz,
    text[],
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;