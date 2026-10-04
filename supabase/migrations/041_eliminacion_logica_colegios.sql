-- ============================================================
-- HuellAPP | Migración 041
-- Eliminación lógica auditada y reutilización de RBD
-- ============================================================
--
-- REGLAS
-- ------------------------------------------------------------
-- - DELETE_SCHOOL se concede inicialmente solo a SUPERADMIN.
-- - No se elimina físicamente el colegio ni sus relaciones.
-- - Se bloquea la eliminación si hay asignaciones futuras activas.
-- - El RBD es único únicamente entre colegios no eliminados.
-- - Eliminación y auditoría ocurren en la misma transacción.
-- - Las RPC se ejecutan exclusivamente desde el backend con
--   service_role; el cliente nunca recibe esta credencial.
--
-- IMPORTANTE
-- ------------------------------------------------------------
-- Ejecutar una sola vez en DEV, tras revisar el respaldo.
-- No ejecutar eliminación desde SQL Editor: esta migración
-- únicamente prepara la funcionalidad y sus permisos.
-- ============================================================

BEGIN;

/* ============================================================
   1. PERMISO DE ELIMINACIÓN
   ============================================================ */

INSERT INTO public.permisos (codigo, nombre, descripcion, modulo, activo)
VALUES (
    'DELETE_SCHOOL',
    'Eliminar colegios',
    'Permite eliminar lógicamente colegios sin asignaciones futuras activas.',
    'COLEGIOS',
    true
)
ON CONFLICT (codigo) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    modulo = EXCLUDED.modulo,
    activo = true;

-- La eliminación se limita inicialmente a SUPERADMIN.
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permisos p ON p.codigo = 'DELETE_SCHOOL'
WHERE r.codigo = 'SUPERADMIN'
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

/* ============================================================
   2. UNICIDAD DE RBD ENTRE COLEGIOS NO ELIMINADOS
   ============================================================ */

-- Primero se crea el índice nuevo para mantener la unicidad
-- incluso durante el cambio de restricción.
CREATE UNIQUE INDEX IF NOT EXISTS uq_colegios_rbd_no_eliminados
ON public.colegios (rbd)
WHERE deleted_at IS NULL;

ALTER TABLE public.colegios
DROP CONSTRAINT IF EXISTS colegios_rbd_key;

/* ============================================================
   3. ADAPTAR LAS RPC DE CREACIÓN Y EDICIÓN
   ============================================================ */

-- Se conservan las funciones 032; únicamente se modifica
-- su validación de RBD para ignorar colegios eliminados.

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
              AND c.deleted_at IS NULL
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
              AND c.deleted_at IS NULL
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


/* ============================================================
   4. ELIMINACIÓN LÓGICA ATÓMICA Y AUDITADA
   ============================================================ */

-- La RPC verifica actor, permiso y ausencia de asignaciones
-- futuras. Bloquea la fila objetivo durante la transacción.
-- Conserva contactos, cursos, salas y asignaciones históricas.
CREATE OR REPLACE FUNCTION public.eliminar_colegio_atomico(
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
    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    /* --------------------------------------------------------
       Actor activo y autorizado
       -------------------------------------------------------- */
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
           AND p.codigo = 'DELETE_SCHOOL'
           AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    /* --------------------------------------------------------
       Colegio objetivo
       -------------------------------------------------------- */
    SELECT *
      INTO v_actual
      FROM public.colegios
     WHERE id = p_colegio_id
     FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    /* --------------------------------------------------------
       Protección de asignaciones futuras activas
       -------------------------------------------------------- */
    IF EXISTS (
        SELECT 1
          FROM public.asignaciones a
         WHERE a.colegio_id = p_colegio_id
           AND a.activo = true
           AND a.deleted_at IS NULL
           AND a.fecha >= CURRENT_DATE
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_HAS_FUTURE_ASSIGNMENTS');
    END IF;

    /* --------------------------------------------------------
       Actualización y auditoría en una sola transacción
       -------------------------------------------------------- */
    v_old_values := public.snapshot_colegio_auditoria(p_colegio_id)
        || jsonb_build_object('deleted_at', v_actual.deleted_at);

    UPDATE public.colegios
       SET activo = false,
           deleted_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP,
           updated_by = p_actor_user_id
     WHERE id = p_colegio_id;

    v_new_values := public.snapshot_colegio_auditoria(p_colegio_id)
        || jsonb_build_object(
            'deleted_at',
            (SELECT deleted_at FROM public.colegios WHERE id = p_colegio_id)
        );

    INSERT INTO public.audit_logs (
        actor_user_id, actor_role_id, action, entity_type,
        entity_id, old_values, new_values, description,
        request_id, ip_address, user_agent, source
    ) VALUES (
        p_actor_user_id, v_actor.rol_id, 'DELETE_SCHOOL', 'SCHOOL',
        p_colegio_id, v_old_values, v_new_values,
        'Eliminación lógica de colegio.',
        p_request_id, p_ip_address, p_user_agent, 'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'colegio_id', p_colegio_id);
END;
$$;

COMMENT ON FUNCTION public.eliminar_colegio_atomico(
    uuid, uuid, uuid, inet, text
) IS 'Elimina lógicamente un colegio sin asignaciones futuras activas y registra DELETE_SCHOOL atómicamente.';

-- SECURITY DEFINER: prohibir llamadas directas desde el cliente.
REVOKE ALL ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text) FROM anon;
REVOKE ALL ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text) TO service_role;

COMMIT;
