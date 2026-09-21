-- ============================================================
-- HuellAPP
-- Migración 030
-- Atomicidad de gestión de usuarios
-- ============================================================
--
-- Convierte en transacciones PostgreSQL atómicas:
-- - actualización de datos básicos;
-- - cambio de rol;
-- - activación;
-- - desactivación;
-- - borrado lógico.
--
-- La creación de usuarios NO se incluye porque combina Supabase Auth
-- con public.usuarios y requiere un tratamiento híbrido separado.
-- ============================================================

BEGIN;


-- ============================================================
-- ACTUALIZAR DATOS BÁSICOS
-- ============================================================

CREATE OR REPLACE FUNCTION public.actualizar_usuario_atomico(
    p_user_id uuid,
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
    v_target record;
    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    SELECT
        u.id,
        u.rol_id,
        r.codigo AS role_code
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
          AND p.codigo = 'UPDATE_USER'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;

    SELECT
        u.*,
        r.codigo AS role_code
    INTO v_target
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_user_id
    FOR UPDATE OF u;

    IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    IF (
        v_actor.role_code = 'DIRECTIVA'
        AND v_target.role_code = 'SUPERADMIN'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;

    IF p_cambios IS NULL
       OR jsonb_typeof(p_cambios) <> 'object'
       OR p_cambios = '{}'::jsonb THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NO_CHANGES'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_object_keys(p_cambios) AS k(key)
        WHERE k.key NOT IN (
            'nombres',
            'apellido_paterno',
            'apellido_materno',
            'telefono'
        )
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_FIELDS'
        );
    END IF;

    IF (
        (p_cambios ? 'nombres'
            AND NULLIF(BTRIM(p_cambios ->> 'nombres'), '') IS NULL)
        OR
        (p_cambios ? 'apellido_paterno'
            AND NULLIF(BTRIM(p_cambios ->> 'apellido_paterno'), '') IS NULL)
        OR
        (p_cambios ? 'apellido_materno'
            AND NULLIF(BTRIM(p_cambios ->> 'apellido_materno'), '') IS NULL)
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_REQUIRED_FIELD'
        );
    END IF;

    v_old_values := jsonb_build_object(
        'rut', v_target.rut,
        'nombres', v_target.nombres,
        'apellido_paterno', v_target.apellido_paterno,
        'apellido_materno', v_target.apellido_materno,
        'email', v_target.email,
        'telefono', v_target.telefono,
        'activo', v_target.activo,
        'role_code', v_target.role_code
    );

    UPDATE public.usuarios
    SET
        nombres = CASE
            WHEN p_cambios ? 'nombres'
                THEN p_cambios ->> 'nombres'
            ELSE nombres
        END,
        apellido_paterno = CASE
            WHEN p_cambios ? 'apellido_paterno'
                THEN p_cambios ->> 'apellido_paterno'
            ELSE apellido_paterno
        END,
        apellido_materno = CASE
            WHEN p_cambios ? 'apellido_materno'
                THEN p_cambios ->> 'apellido_materno'
            ELSE apellido_materno
        END,
        telefono = CASE
            WHEN p_cambios ? 'telefono'
                THEN p_cambios ->> 'telefono'
            ELSE telefono
        END,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;

    SELECT jsonb_build_object(
        'rut', u.rut,
        'nombres', u.nombres,
        'apellido_paterno', u.apellido_paterno,
        'apellido_materno', u.apellido_materno,
        'email', u.email,
        'telefono', u.telefono,
        'activo', u.activo,
        'role_code', r.codigo
    )
    INTO v_new_values
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_user_id;

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
        'UPDATE_USER',
        'USER',
        p_user_id,
        v_old_values,
        v_new_values,
        'Actualización de datos de usuario.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id
    );
END;
$$;


-- ============================================================
-- CAMBIAR ROL
-- ============================================================

CREATE OR REPLACE FUNCTION public.cambiar_rol_usuario_atomico(
    p_user_id uuid,
    p_role_code varchar,
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
    v_target record;
    v_new_role record;
BEGIN
    SELECT
        u.id,
        u.rol_id,
        r.codigo AS role_code
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
          AND p.codigo = 'CHANGE_USER_ROLE'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;

    SELECT
        u.id,
        u.rol_id,
        u.deleted_at,
        r.codigo AS role_code
    INTO v_target
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_user_id
    FOR UPDATE OF u;

    IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    SELECT
        r.id,
        r.codigo,
        r.nombre
    INTO v_new_role
    FROM public.roles r
    WHERE r.codigo = UPPER(BTRIM(p_role_code))
      AND r.activo = true
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ROLE_NOT_FOUND'
        );
    END IF;

    IF (
        v_actor.role_code = 'DIRECTIVA'
        AND (
            v_target.role_code = 'SUPERADMIN'
            OR v_new_role.codigo = 'SUPERADMIN'
        )
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;

    IF v_target.rol_id = v_new_role.id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'SAME_ROLE'
        );
    END IF;

    UPDATE public.usuarios
    SET
        rol_id = v_new_role.id,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;

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
        'CHANGE_USER_ROLE',
        'USER',
        p_user_id,
        jsonb_build_object(
            'role_code', v_target.role_code
        ),
        jsonb_build_object(
            'role_code', v_new_role.codigo
        ),
        'Cambio de rol de usuario.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id
    );
END;
$$;


-- ============================================================
-- ACTIVAR
-- ============================================================

CREATE OR REPLACE FUNCTION public.activar_usuario_atomico(
    p_user_id uuid,
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
    v_target record;
BEGIN
    SELECT
        u.id,
        u.rol_id,
        r.codigo AS role_code
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
          AND p.codigo = 'ACTIVATE_USER'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;

    SELECT
        u.id,
        u.activo,
        u.deleted_at,
        r.codigo AS role_code
    INTO v_target
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_user_id
    FOR UPDATE OF u;

    IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    IF (
        v_actor.role_code = 'DIRECTIVA'
        AND v_target.role_code = 'SUPERADMIN'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;

    IF v_target.activo IS TRUE THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ALREADY_ACTIVE'
        );
    END IF;

    UPDATE public.usuarios
    SET
        activo = true,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;

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
        'ACTIVATE_USER',
        'USER',
        p_user_id,
        jsonb_build_object('activo', false),
        jsonb_build_object('activo', true),
        'Activación de usuario.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id
    );
END;
$$;


-- ============================================================
-- DESACTIVAR
-- ============================================================

CREATE OR REPLACE FUNCTION public.desactivar_usuario_atomico(
    p_user_id uuid,
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
    v_target record;
BEGIN
    SELECT
        u.id,
        u.rol_id,
        r.codigo AS role_code
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
          AND p.codigo = 'DEACTIVATE_USER'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;

    SELECT
        u.id,
        u.activo,
        u.deleted_at,
        r.codigo AS role_code
    INTO v_target
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_user_id
    FOR UPDATE OF u;

    IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    IF (
        v_actor.role_code = 'DIRECTIVA'
        AND v_target.role_code = 'SUPERADMIN'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;

    IF v_target.activo IS FALSE THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ALREADY_INACTIVE'
        );
    END IF;

    UPDATE public.usuarios
    SET
        activo = false,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;

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
        'DEACTIVATE_USER',
        'USER',
        p_user_id,
        jsonb_build_object('activo', true),
        jsonb_build_object('activo', false),
        'Desactivación de usuario.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id
    );
END;
$$;


-- ============================================================
-- BORRADO LÓGICO
-- ============================================================

CREATE OR REPLACE FUNCTION public.eliminar_usuario_atomico(
    p_user_id uuid,
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
    v_target record;
    v_deleted_at timestamptz;
BEGIN
    SELECT
        u.id,
        u.rol_id,
        r.codigo AS role_code
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
          AND p.codigo = 'DELETE_USER'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;

    IF p_user_id = p_actor_user_id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'SELF_DELETE'
        );
    END IF;

    SELECT
        u.*,
        r.codigo AS role_code
    INTO v_target
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = p_user_id
    FOR UPDATE OF u;

    IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_NOT_FOUND'
        );
    END IF;

    IF (
        v_actor.role_code = 'DIRECTIVA'
        AND v_target.role_code = 'SUPERADMIN'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;

    v_deleted_at := CURRENT_TIMESTAMP;

    UPDATE public.usuarios
    SET
        activo = false,
        deleted_at = v_deleted_at,
        updated_by = p_actor_user_id,
        updated_at = v_deleted_at
    WHERE id = p_user_id;

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
        'DELETE_USER',
        'USER',
        p_user_id,
        jsonb_build_object(
            'rut', v_target.rut,
            'nombres', v_target.nombres,
            'apellido_paterno', v_target.apellido_paterno,
            'apellido_materno', v_target.apellido_materno,
            'email', v_target.email,
            'telefono', v_target.telefono,
            'activo', v_target.activo,
            'deleted_at', v_target.deleted_at,
            'role_code', v_target.role_code
        ),
        jsonb_build_object(
            'activo', false,
            'deleted_at', v_deleted_at,
            'role_code', v_target.role_code
        ),
        'Borrado lógico de usuario.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id,
        'deleted_at', v_deleted_at
    );
END;
$$;


-- ============================================================
-- COMENTARIOS
-- ============================================================

COMMENT ON FUNCTION public.actualizar_usuario_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) IS
'Actualiza datos básicos de un usuario y registra auditoría en una sola transacción.';

COMMENT ON FUNCTION public.cambiar_rol_usuario_atomico(
    uuid, varchar, uuid, uuid, inet, text
) IS
'Cambia el rol de un usuario y registra auditoría en una sola transacción.';

COMMENT ON FUNCTION public.activar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Activa un usuario y registra auditoría en una sola transacción.';

COMMENT ON FUNCTION public.desactivar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Desactiva un usuario y registra auditoría en una sola transacción.';

COMMENT ON FUNCTION public.eliminar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Realiza borrado lógico de usuario y registra auditoría en una sola transacción.';


-- ============================================================
-- SEGURIDAD DE EJECUCIÓN
-- ============================================================

REVOKE ALL ON FUNCTION public.actualizar_usuario_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.actualizar_usuario_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.actualizar_usuario_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_usuario_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.cambiar_rol_usuario_atomico(
    uuid, varchar, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cambiar_rol_usuario_atomico(
    uuid, varchar, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.cambiar_rol_usuario_atomico(
    uuid, varchar, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cambiar_rol_usuario_atomico(
    uuid, varchar, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.activar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.activar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.activar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.desactivar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.desactivar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.desactivar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.desactivar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.eliminar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.eliminar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.eliminar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_usuario_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;


COMMIT;
