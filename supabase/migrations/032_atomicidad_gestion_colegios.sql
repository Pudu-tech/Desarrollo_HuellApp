-- ============================================================
-- HuellAPP
-- Migración 032
-- Atomicidad de gestión de colegios
-- ============================================================
--
-- Flujos migrados:
-- - crear colegio;
-- - actualizar colegio;
-- - activar colegio;
-- - desactivar colegio.
--
-- Cada operación crítica y su auditoría se ejecutan dentro de
-- una única transacción PostgreSQL.
-- ============================================================

BEGIN;


-- ============================================================
-- HELPER INTERNO: SNAPSHOT DE COLEGIO
-- ============================================================

CREATE OR REPLACE FUNCTION public.snapshot_colegio_auditoria(
    p_colegio_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', c.id,
        'rbd', c.rbd,
        'nombre', c.nombre,
        'descripcion', c.descripcion,
        'tipo_dependencia_id', c.tipo_dependencia_id,
        'direccion', c.direccion,
        'numero', c.numero,
        'complemento', c.complemento,
        'comuna_id', c.comuna_id,
        'region_id', c.region_id,
        'codigo_postal', c.codigo_postal,
        'telefono', c.telefono,
        'email', c.email,
        'sitio_web', c.sitio_web,
        'nombre_contacto', c.nombre_contacto,
        'telefono_contacto', c.telefono_contacto,
        'email_contacto', c.email_contacto,
        'activo', c.activo
    )
    FROM public.colegios c
    WHERE c.id = p_colegio_id;
$$;


-- ============================================================
-- CREAR COLEGIO
-- ============================================================

CREATE OR REPLACE FUNCTION public.crear_colegio_atomico(
    p_datos jsonb,
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
    v_colegio_id uuid;
    v_region_id uuid;
    v_comuna_id uuid;
    v_tipo_dependencia_id uuid;
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
        JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'CREATE_SCHOOL'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
    END IF;

    IF NULLIF(BTRIM(p_datos ->> 'nombre'), '') IS NULL
       OR NULLIF(BTRIM(p_datos ->> 'direccion'), '') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_REQUIRED_FIELD');
    END IF;

    BEGIN
        v_region_id := (p_datos ->> 'region_id')::uuid;
        v_comuna_id := (p_datos ->> 'comuna_id')::uuid;

        IF NULLIF(p_datos ->> 'tipo_dependencia_id', '') IS NOT NULL THEN
            v_tipo_dependencia_id := (p_datos ->> 'tipo_dependencia_id')::uuid;
        ELSE
            v_tipo_dependencia_id := NULL;
        END IF;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_RELATION_ID');
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM public.regiones r
        WHERE r.id = v_region_id
          AND r.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'REGION_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.comunas c
        WHERE c.id = v_comuna_id
          AND c.region_id = v_region_id
          AND c.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COMUNA_NOT_FOUND_OR_MISMATCH');
    END IF;

    IF v_tipo_dependencia_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.tipos_dependencia td
            WHERE td.id = v_tipo_dependencia_id
              AND td.activo = true
       ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'DEPENDENCY_TYPE_NOT_FOUND');
    END IF;

    IF NULLIF(BTRIM(p_datos ->> 'rbd'), '') IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM public.colegios c
            WHERE c.rbd = BTRIM(p_datos ->> 'rbd')
       ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'RBD_EXISTS');
    END IF;

    BEGIN
        INSERT INTO public.colegios (
            rbd,
            nombre,
            descripcion,
            tipo_dependencia_id,
            direccion,
            numero,
            complemento,
            comuna_id,
            region_id,
            codigo_postal,
            telefono,
            email,
            sitio_web,
            nombre_contacto,
            telefono_contacto,
            email_contacto,
            activo,
            created_by,
            updated_by
        )
        VALUES (
            NULLIF(BTRIM(p_datos ->> 'rbd'), ''),
            BTRIM(p_datos ->> 'nombre'),
            NULLIF(BTRIM(p_datos ->> 'descripcion'), ''),
            v_tipo_dependencia_id,
            BTRIM(p_datos ->> 'direccion'),
            NULLIF(BTRIM(p_datos ->> 'numero'), ''),
            NULLIF(BTRIM(p_datos ->> 'complemento'), ''),
            v_comuna_id,
            v_region_id,
            NULLIF(BTRIM(p_datos ->> 'codigo_postal'), ''),
            NULLIF(BTRIM(p_datos ->> 'telefono'), ''),
            NULLIF(BTRIM(p_datos ->> 'email'), ''),
            NULLIF(BTRIM(p_datos ->> 'sitio_web'), ''),
            NULLIF(BTRIM(p_datos ->> 'nombre_contacto'), ''),
            NULLIF(BTRIM(p_datos ->> 'telefono_contacto'), ''),
            NULLIF(BTRIM(p_datos ->> 'email_contacto'), ''),
            true,
            p_actor_user_id,
            p_actor_user_id
        )
        RETURNING id INTO v_colegio_id;

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'RBD_EXISTS');
    END;

    v_new_values := public.snapshot_colegio_auditoria(v_colegio_id);

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
        'CREATE_SCHOOL',
        'SCHOOL',
        v_colegio_id,
        NULL,
        v_new_values,
        'Creación de colegio.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'colegio_id', v_colegio_id
    );
END;
$$;


-- ============================================================
-- ACTUALIZAR COLEGIO
-- ============================================================

CREATE OR REPLACE FUNCTION public.actualizar_colegio_atomico(
    p_colegio_id uuid,
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
    v_region_id uuid;
    v_comuna_id uuid;
    v_tipo_dependencia_id uuid;
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
        JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'UPDATE_SCHOOL'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.colegios
    WHERE id = p_colegio_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
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
            'rbd',
            'nombre',
            'descripcion',
            'tipo_dependencia_id',
            'direccion',
            'numero',
            'complemento',
            'comuna_id',
            'region_id',
            'codigo_postal',
            'telefono',
            'email',
            'sitio_web',
            'nombre_contacto',
            'telefono_contacto',
            'email_contacto'
        )
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_FIELDS');
    END IF;

    IF (p_cambios ? 'nombre'
        AND NULLIF(BTRIM(p_cambios ->> 'nombre'), '') IS NULL)
       OR
       (p_cambios ? 'direccion'
        AND NULLIF(BTRIM(p_cambios ->> 'direccion'), '') IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_REQUIRED_FIELD');
    END IF;

    BEGIN
        v_region_id := CASE
            WHEN p_cambios ? 'region_id'
                THEN (p_cambios ->> 'region_id')::uuid
            ELSE v_actual.region_id
        END;

        v_comuna_id := CASE
            WHEN p_cambios ? 'comuna_id'
                THEN (p_cambios ->> 'comuna_id')::uuid
            ELSE v_actual.comuna_id
        END;

        v_tipo_dependencia_id := CASE
            WHEN p_cambios ? 'tipo_dependencia_id' THEN
                CASE
                    WHEN NULLIF(p_cambios ->> 'tipo_dependencia_id', '') IS NULL
                        THEN NULL
                    ELSE (p_cambios ->> 'tipo_dependencia_id')::uuid
                END
            ELSE v_actual.tipo_dependencia_id
        END;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_RELATION_ID');
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM public.regiones r
        WHERE r.id = v_region_id
          AND r.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'REGION_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.comunas c
        WHERE c.id = v_comuna_id
          AND c.region_id = v_region_id
          AND c.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COMUNA_NOT_FOUND_OR_MISMATCH');
    END IF;

    IF v_tipo_dependencia_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.tipos_dependencia td
            WHERE td.id = v_tipo_dependencia_id
              AND td.activo = true
       ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'DEPENDENCY_TYPE_NOT_FOUND');
    END IF;

    IF p_cambios ? 'rbd'
       AND NULLIF(BTRIM(p_cambios ->> 'rbd'), '') IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM public.colegios c
            WHERE c.rbd = BTRIM(p_cambios ->> 'rbd')
              AND c.id <> p_colegio_id
       ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'RBD_EXISTS');
    END IF;

    v_old_values := public.snapshot_colegio_auditoria(p_colegio_id);

    BEGIN
        UPDATE public.colegios
        SET
            rbd = CASE
                WHEN p_cambios ? 'rbd'
                    THEN NULLIF(BTRIM(p_cambios ->> 'rbd'), '')
                ELSE rbd
            END,
            nombre = CASE
                WHEN p_cambios ? 'nombre'
                    THEN BTRIM(p_cambios ->> 'nombre')
                ELSE nombre
            END,
            descripcion = CASE
                WHEN p_cambios ? 'descripcion'
                    THEN NULLIF(BTRIM(p_cambios ->> 'descripcion'), '')
                ELSE descripcion
            END,
            tipo_dependencia_id = v_tipo_dependencia_id,
            direccion = CASE
                WHEN p_cambios ? 'direccion'
                    THEN BTRIM(p_cambios ->> 'direccion')
                ELSE direccion
            END,
            numero = CASE
                WHEN p_cambios ? 'numero'
                    THEN NULLIF(BTRIM(p_cambios ->> 'numero'), '')
                ELSE numero
            END,
            complemento = CASE
                WHEN p_cambios ? 'complemento'
                    THEN NULLIF(BTRIM(p_cambios ->> 'complemento'), '')
                ELSE complemento
            END,
            comuna_id = v_comuna_id,
            region_id = v_region_id,
            codigo_postal = CASE
                WHEN p_cambios ? 'codigo_postal'
                    THEN NULLIF(BTRIM(p_cambios ->> 'codigo_postal'), '')
                ELSE codigo_postal
            END,
            telefono = CASE
                WHEN p_cambios ? 'telefono'
                    THEN NULLIF(BTRIM(p_cambios ->> 'telefono'), '')
                ELSE telefono
            END,
            email = CASE
                WHEN p_cambios ? 'email'
                    THEN NULLIF(BTRIM(p_cambios ->> 'email'), '')
                ELSE email
            END,
            sitio_web = CASE
                WHEN p_cambios ? 'sitio_web'
                    THEN NULLIF(BTRIM(p_cambios ->> 'sitio_web'), '')
                ELSE sitio_web
            END,
            nombre_contacto = CASE
                WHEN p_cambios ? 'nombre_contacto'
                    THEN NULLIF(BTRIM(p_cambios ->> 'nombre_contacto'), '')
                ELSE nombre_contacto
            END,
            telefono_contacto = CASE
                WHEN p_cambios ? 'telefono_contacto'
                    THEN NULLIF(BTRIM(p_cambios ->> 'telefono_contacto'), '')
                ELSE telefono_contacto
            END,
            email_contacto = CASE
                WHEN p_cambios ? 'email_contacto'
                    THEN NULLIF(BTRIM(p_cambios ->> 'email_contacto'), '')
                ELSE email_contacto
            END,
            updated_by = p_actor_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_colegio_id;

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'RBD_EXISTS');
    END;

    v_new_values := public.snapshot_colegio_auditoria(p_colegio_id);

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
        'UPDATE_SCHOOL',
        'SCHOOL',
        p_colegio_id,
        v_old_values,
        v_new_values,
        'Actualización de colegio.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'colegio_id', p_colegio_id);
END;
$$;


-- ============================================================
-- ACTIVAR COLEGIO
-- ============================================================

CREATE OR REPLACE FUNCTION public.activar_colegio_atomico(
    p_colegio_id uuid,
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
        JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'ACTIVATE_SCHOOL'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.colegios
    WHERE id = p_colegio_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    IF v_actual.activo IS TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ALREADY_ACTIVE');
    END IF;

    UPDATE public.colegios
    SET
        activo = true,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_colegio_id;

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
        'ACTIVATE_SCHOOL',
        'SCHOOL',
        p_colegio_id,
        jsonb_build_object('activo', false),
        jsonb_build_object('activo', true),
        'Activación de colegio.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'colegio_id', p_colegio_id);
END;
$$;


-- ============================================================
-- DESACTIVAR COLEGIO
-- ============================================================

CREATE OR REPLACE FUNCTION public.desactivar_colegio_atomico(
    p_colegio_id uuid,
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
        JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'DEACTIVATE_SCHOOL'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.colegios
    WHERE id = p_colegio_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    IF v_actual.activo IS FALSE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ALREADY_INACTIVE');
    END IF;

    UPDATE public.colegios
    SET
        activo = false,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_colegio_id;

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
        'DEACTIVATE_SCHOOL',
        'SCHOOL',
        p_colegio_id,
        jsonb_build_object('activo', true),
        jsonb_build_object('activo', false),
        'Desactivación de colegio.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'colegio_id', p_colegio_id);
END;
$$;


-- ============================================================
-- COMENTARIOS
-- ============================================================

COMMENT ON FUNCTION public.crear_colegio_atomico(
    jsonb, uuid, uuid, inet, text
) IS
'Crea un colegio y registra CREATE_SCHOOL de forma atómica.';

COMMENT ON FUNCTION public.actualizar_colegio_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) IS
'Actualiza un colegio y registra UPDATE_SCHOOL de forma atómica.';

COMMENT ON FUNCTION public.activar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Activa un colegio y registra ACTIVATE_SCHOOL de forma atómica.';

COMMENT ON FUNCTION public.desactivar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Desactiva un colegio y registra DEACTIVATE_SCHOOL de forma atómica.';


-- ============================================================
-- SEGURIDAD DE EJECUCIÓN
-- ============================================================

REVOKE ALL ON FUNCTION public.snapshot_colegio_auditoria(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.snapshot_colegio_auditoria(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.snapshot_colegio_auditoria(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.snapshot_colegio_auditoria(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.crear_colegio_atomico(
    jsonb, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crear_colegio_atomico(
    jsonb, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.crear_colegio_atomico(
    jsonb, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.crear_colegio_atomico(
    jsonb, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.actualizar_colegio_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.actualizar_colegio_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.actualizar_colegio_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_colegio_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.activar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.activar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.activar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.desactivar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.desactivar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.desactivar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.desactivar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;


COMMIT;
