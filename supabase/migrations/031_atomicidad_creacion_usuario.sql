-- ============================================================
-- HuellAPP
-- Migración 031
-- Atomicidad PostgreSQL de creación de usuario
-- ============================================================
--
-- Supabase Auth permanece fuera de la transacción PostgreSQL.
--
-- Flujo esperado desde FastAPI:
-- 1. crear identidad en Supabase Auth;
-- 2. llamar esta RPC con el UUID creado por Auth;
-- 3. PostgreSQL crea public.usuarios + audit_logs atómicamente;
-- 4. si la RPC falla, FastAPI elimina compensatoriamente
--    la identidad recién creada en Supabase Auth.
--
-- La contraseña nunca entra a esta función ni se almacena en
-- public.usuarios o audit_logs.
-- ============================================================

BEGIN;


CREATE OR REPLACE FUNCTION public.crear_usuario_atomico(
    p_user_id uuid,
    p_rut text,
    p_nombres text,
    p_apellido_paterno text,
    p_apellido_materno text,
    p_email text,
    p_telefono text,
    p_role_code text,
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
    v_role record;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- Actor autenticado y activo.
    -- --------------------------------------------------------
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

    -- --------------------------------------------------------
    -- Defensa en profundidad: CREATE_USER también se valida
    -- dentro de PostgreSQL.
    -- --------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
            ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'CREATE_USER'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;

    -- --------------------------------------------------------
    -- Rol solicitado.
    -- --------------------------------------------------------
    SELECT
        r.id,
        r.codigo,
        r.nombre
    INTO v_role
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
        AND v_role.codigo = 'SUPERADMIN'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;

    -- --------------------------------------------------------
    -- Validaciones mínimas que nunca deben depender solo de
    -- FastAPI. La validación completa de RUT/nombres/email se
    -- mantiene en Pydantic.
    -- --------------------------------------------------------
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_USER_ID'
        );
    END IF;

    IF NULLIF(BTRIM(p_rut), '') IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_RUT'
        );
    END IF;

    IF NULLIF(BTRIM(p_nombres), '') IS NULL
       OR NULLIF(BTRIM(p_apellido_paterno), '') IS NULL
       OR NULLIF(BTRIM(p_apellido_materno), '') IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_NAME'
        );
    END IF;

    IF NULLIF(BTRIM(p_email), '') IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_EMAIL'
        );
    END IF;

    -- --------------------------------------------------------
    -- Duplicados.
    --
    -- Se consideran también usuarios eliminados lógicamente,
    -- manteniendo la regla actual de no reutilizar RUT/correo.
    -- --------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE u.id = p_user_id
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'USER_ID_EXISTS'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE u.rut = BTRIM(p_rut)
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'RUT_EXISTS'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE LOWER(u.email) = LOWER(BTRIM(p_email))
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'EMAIL_EXISTS'
        );
    END IF;

    -- --------------------------------------------------------
    -- Perfil + auditoría.
    --
    -- Ambas escrituras pertenecen a la misma transacción de la
    -- función. Si cualquiera falla, PostgreSQL revierte las dos.
    -- --------------------------------------------------------
    BEGIN
        INSERT INTO public.usuarios (
            id,
            rut,
            nombres,
            apellido_paterno,
            apellido_materno,
            email,
            telefono,
            rol_id,
            activo,
            created_by,
            updated_by
        )
        VALUES (
            p_user_id,
            BTRIM(p_rut),
            BTRIM(p_nombres),
            BTRIM(p_apellido_paterno),
            BTRIM(p_apellido_materno),
            LOWER(BTRIM(p_email)),
            NULLIF(BTRIM(p_telefono), ''),
            v_role.id,
            true,
            p_actor_user_id,
            p_actor_user_id
        );

        v_new_values := jsonb_build_object(
            'id', p_user_id,
            'rut', BTRIM(p_rut),
            'nombres', BTRIM(p_nombres),
            'apellido_paterno', BTRIM(p_apellido_paterno),
            'apellido_materno', BTRIM(p_apellido_materno),
            'email', LOWER(BTRIM(p_email)),
            'telefono', NULLIF(BTRIM(p_telefono), ''),
            'activo', true,
            'role_code', v_role.codigo
        );

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
            'CREATE_USER',
            'USER',
            p_user_id,
            NULL,
            v_new_values,
            'Creación de usuario.',
            p_request_id,
            p_ip_address,
            p_user_agent,
            'WEB'
        );

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object(
                'ok', false,
                'error_code', 'DUPLICATE_USER'
            );
    END;

    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id,
        'usuario', jsonb_build_object(
            'id', p_user_id,
            'rut', BTRIM(p_rut),
            'nombres', BTRIM(p_nombres),
            'apellido_paterno', BTRIM(p_apellido_paterno),
            'apellido_materno', BTRIM(p_apellido_materno),
            'email', LOWER(BTRIM(p_email)),
            'telefono', NULLIF(BTRIM(p_telefono), ''),
            'activo', true,
            'roles', jsonb_build_object(
                'codigo', v_role.codigo,
                'nombre', v_role.nombre
            )
        )
    );
END;
$$;


COMMENT ON FUNCTION public.crear_usuario_atomico(
    uuid,
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    uuid,
    uuid,
    inet,
    text
) IS
'Crea public.usuarios y su auditoría CREATE_USER atómicamente. La identidad Supabase Auth se crea previamente desde FastAPI.';


-- ============================================================
-- Seguridad
-- ============================================================

REVOKE ALL ON FUNCTION public.crear_usuario_atomico(
    uuid,
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.crear_usuario_atomico(
    uuid,
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.crear_usuario_atomico(
    uuid,
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.crear_usuario_atomico(
    uuid,
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;
