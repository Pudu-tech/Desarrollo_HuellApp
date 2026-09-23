-- ============================================================
-- HuellAPP
-- Migración 034
-- Atomicidad de gestión de salas
-- ============================================================
--
-- Flujos migrados:
-- - crear sala;
-- - actualizar sala;
-- - activar sala;
-- - desactivar sala.
--
-- Cada cambio y su audit_log quedan dentro de la misma
-- transacción PostgreSQL.
-- ============================================================

BEGIN;


-- ============================================================
-- SNAPSHOT INTERNO PARA AUDITORÍA
-- ============================================================

CREATE OR REPLACE FUNCTION public.snapshot_sala_auditoria(
    p_sala_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', s.id,
        'colegio_id', s.colegio_id,
        'nombre', s.nombre,
        'descripcion', s.descripcion,
        'capacidad', s.capacidad,
        'ubicacion', s.ubicacion,
        'activo', s.activo,
        'created_at', s.created_at,
        'updated_at', s.updated_at
    )
    FROM public.salas s
    WHERE s.id = p_sala_id;
$$;


-- ============================================================
-- CREAR SALA
-- ============================================================

CREATE OR REPLACE FUNCTION public.crear_sala_atomica(
    p_colegio_id uuid,
    p_nombre text,
    p_descripcion text,
    p_capacidad integer,
    p_ubicacion text,
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
    v_sala_id uuid;
    v_nombre text;
    v_new_values jsonb;
BEGIN
    SELECT u.id, u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
          ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'CREATE_ROOM'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    v_nombre := BTRIM(p_nombre);

    IF NULLIF(v_nombre, '') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_NAME');
    END IF;

    IF p_capacidad IS NOT NULL
       AND (p_capacidad < 1 OR p_capacidad > 1000) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_CAPACITY');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.colegios c
        WHERE c.id = p_colegio_id
          AND c.activo = true
          AND c.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_ACTIVE');
    END IF;

    -- La constraint uq_sala_colegio_nombre abarca todos los registros.
    IF EXISTS (
        SELECT 1
        FROM public.salas s
        WHERE s.colegio_id = p_colegio_id
          AND s.nombre = v_nombre
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_EXISTS');
    END IF;

    BEGIN
        INSERT INTO public.salas (
            colegio_id,
            nombre,
            descripcion,
            capacidad,
            ubicacion,
            activo,
            created_by,
            updated_by
        )
        VALUES (
            p_colegio_id,
            v_nombre,
            NULLIF(BTRIM(p_descripcion), ''),
            p_capacidad,
            NULLIF(BTRIM(p_ubicacion), ''),
            true,
            p_actor_user_id,
            p_actor_user_id
        )
        RETURNING id INTO v_sala_id;

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_EXISTS');
    END;

    v_new_values := public.snapshot_sala_auditoria(v_sala_id);

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
        'CREATE_ROOM',
        'ROOM',
        v_sala_id,
        NULL,
        v_new_values,
        'Creación de sala.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'sala_id', v_sala_id
    );
END;
$$;


-- ============================================================
-- ACTUALIZAR SALA
-- ============================================================

CREATE OR REPLACE FUNCTION public.actualizar_sala_atomica(
    p_sala_id uuid,
    p_cambios jsonb,
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
    v_actual record;
    v_colegio_id uuid;
    v_nombre text;
    v_descripcion text;
    v_capacidad integer;
    v_ubicacion text;
    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    SELECT u.id, u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
          ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'UPDATE_ROOM'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.salas
    WHERE id = p_sala_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_NOT_FOUND');
    END IF;

    IF p_cambios IS NULL
       OR jsonb_typeof(p_cambios) <> 'object'
       OR p_cambios = '{}'::jsonb THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'NO_CHANGES');
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_object_keys(p_cambios) AS k(key)
        WHERE k.key NOT IN (
            'colegio_id',
            'nombre',
            'descripcion',
            'capacidad',
            'ubicacion'
        )
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_FIELDS');
    END IF;

    BEGIN
        v_colegio_id := CASE
            WHEN p_cambios ? 'colegio_id'
                THEN (p_cambios ->> 'colegio_id')::uuid
            ELSE v_actual.colegio_id
        END;

        v_capacidad := CASE
            WHEN p_cambios ? 'capacidad' THEN
                CASE
                    WHEN p_cambios -> 'capacidad' = 'null'::jsonb
                        THEN NULL
                    ELSE (p_cambios ->> 'capacidad')::integer
                END
            ELSE v_actual.capacidad
        END;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
    END;

    v_nombre := CASE
        WHEN p_cambios ? 'nombre'
            THEN BTRIM(p_cambios ->> 'nombre')
        ELSE v_actual.nombre
    END;

    v_descripcion := CASE
        WHEN p_cambios ? 'descripcion'
            THEN NULLIF(BTRIM(p_cambios ->> 'descripcion'), '')
        ELSE v_actual.descripcion
    END;

    v_ubicacion := CASE
        WHEN p_cambios ? 'ubicacion'
            THEN NULLIF(BTRIM(p_cambios ->> 'ubicacion'), '')
        ELSE v_actual.ubicacion
    END;

    IF NULLIF(v_nombre, '') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_NAME');
    END IF;

    IF v_capacidad IS NOT NULL
       AND (v_capacidad < 1 OR v_capacidad > 1000) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_CAPACITY');
    END IF;

    -- Se conserva la regla actual: el colegio se valida
    -- cuando se intenta cambiar colegio_id.
    IF p_cambios ? 'colegio_id' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.colegios c
            WHERE c.id = v_colegio_id
              AND c.activo = true
              AND c.deleted_at IS NULL
        ) THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_ACTIVE');
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.salas s
        WHERE s.colegio_id = v_colegio_id
          AND s.nombre = v_nombre
          AND s.id <> p_sala_id
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_EXISTS');
    END IF;

    v_old_values := public.snapshot_sala_auditoria(p_sala_id);

    BEGIN
        UPDATE public.salas
        SET
            colegio_id = v_colegio_id,
            nombre = v_nombre,
            descripcion = v_descripcion,
            capacidad = v_capacidad,
            ubicacion = v_ubicacion,
            updated_by = p_actor_user_id
        WHERE id = p_sala_id;

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_EXISTS');
    END;

    v_new_values := public.snapshot_sala_auditoria(p_sala_id);

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
        'UPDATE_ROOM',
        'ROOM',
        p_sala_id,
        v_old_values,
        v_new_values,
        'Actualización de sala.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'sala_id', p_sala_id);
END;
$$;


-- ============================================================
-- ACTIVAR SALA
-- ============================================================

CREATE OR REPLACE FUNCTION public.activar_sala_atomica(
    p_sala_id uuid,
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
    v_actual record;
BEGIN
    SELECT u.id, u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
          ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'ACTIVATE_ROOM'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.salas
    WHERE id = p_sala_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_NOT_FOUND');
    END IF;

    IF v_actual.activo IS TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ALREADY_ACTIVE');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.colegios c
        WHERE c.id = v_actual.colegio_id
          AND c.activo = true
          AND c.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_ACTIVE');
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.salas s
        WHERE s.colegio_id = v_actual.colegio_id
          AND s.nombre = v_actual.nombre
          AND s.id <> p_sala_id
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_EXISTS');
    END IF;

    UPDATE public.salas
    SET
        activo = true,
        updated_by = p_actor_user_id
    WHERE id = p_sala_id;

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
        'ACTIVATE_ROOM',
        'ROOM',
        p_sala_id,
        jsonb_build_object('activo', false),
        jsonb_build_object('activo', true),
        'Activación de sala.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'sala_id', p_sala_id);
END;
$$;


-- ============================================================
-- DESACTIVAR SALA
-- ============================================================

CREATE OR REPLACE FUNCTION public.desactivar_sala_atomica(
    p_sala_id uuid,
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
    v_actual record;
BEGIN
    SELECT u.id, u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
          ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'DEACTIVATE_ROOM'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.salas
    WHERE id = p_sala_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_NOT_FOUND');
    END IF;

    IF v_actual.activo IS FALSE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ALREADY_INACTIVE');
    END IF;

    UPDATE public.salas
    SET
        activo = false,
        updated_by = p_actor_user_id
    WHERE id = p_sala_id;

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
        'DEACTIVATE_ROOM',
        'ROOM',
        p_sala_id,
        jsonb_build_object('activo', true),
        jsonb_build_object('activo', false),
        'Desactivación de sala.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'sala_id', p_sala_id);
END;
$$;


-- ============================================================
-- COMENTARIOS
-- ============================================================

COMMENT ON FUNCTION public.crear_sala_atomica(
    uuid, text, text, integer, text, uuid, uuid, inet, text
) IS
'Crea una sala y registra CREATE_ROOM de forma atómica.';

COMMENT ON FUNCTION public.actualizar_sala_atomica(
    uuid, jsonb, uuid, uuid, inet, text
) IS
'Actualiza una sala y registra UPDATE_ROOM de forma atómica.';

COMMENT ON FUNCTION public.activar_sala_atomica(
    uuid, uuid, uuid, inet, text
) IS
'Activa una sala y registra ACTIVATE_ROOM de forma atómica.';

COMMENT ON FUNCTION public.desactivar_sala_atomica(
    uuid, uuid, uuid, inet, text
) IS
'Desactiva una sala y registra DEACTIVATE_ROOM de forma atómica.';


-- ============================================================
-- SEGURIDAD
-- ============================================================

REVOKE ALL ON FUNCTION public.snapshot_sala_auditoria(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.snapshot_sala_auditoria(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.snapshot_sala_auditoria(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.snapshot_sala_auditoria(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.crear_sala_atomica(
    uuid, text, text, integer, text, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crear_sala_atomica(
    uuid, text, text, integer, text, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.crear_sala_atomica(
    uuid, text, text, integer, text, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.crear_sala_atomica(
    uuid, text, text, integer, text, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.actualizar_sala_atomica(
    uuid, jsonb, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.actualizar_sala_atomica(
    uuid, jsonb, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.actualizar_sala_atomica(
    uuid, jsonb, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_sala_atomica(
    uuid, jsonb, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.activar_sala_atomica(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activar_sala_atomica(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.activar_sala_atomica(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.activar_sala_atomica(
    uuid, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.desactivar_sala_atomica(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.desactivar_sala_atomica(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.desactivar_sala_atomica(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.desactivar_sala_atomica(
    uuid, uuid, uuid, inet, text
) TO service_role;


COMMIT;
