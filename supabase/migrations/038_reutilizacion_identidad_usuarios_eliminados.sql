-- ============================================================
-- HuellAPP
-- Migración 038
-- Permitir reutilización de RUT/correo de usuarios eliminados
-- ============================================================
--
-- REGLA FUNCIONAL
-- ------------------------------------------------------------
-- Un usuario eliminado lógicamente:
--
--   deleted_at IS NOT NULL
--
-- conserva su registro histórico, pero deja disponible su
-- RUT y correo para una futura cuenta nueva.
--
-- Los usuarios activos o desactivados continúan reservando
-- su RUT y correo.
--
-- La migración 037 ya dejó índices UNIQUE parciales:
--
--   uq_usuarios_email_no_eliminado
--   uq_usuarios_rut_no_eliminado
--
-- Esta migración alinea crear_usuario_atomico con esa regla.
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
AS $function$
DECLARE
    v_actor record;
    v_role record;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- Actor autenticado y activo
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
    -- Permiso CREATE_USER
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
    -- Rol solicitado
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
    -- Validaciones mínimas
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
    -- Duplicado por UUID
    -- --------------------------------------------------------
    --
    -- El UUID de Auth debe continuar siendo único globalmente.
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


    -- --------------------------------------------------------
    -- Duplicado por RUT
    -- --------------------------------------------------------
    --
    -- Solo usuarios NO eliminados reservan el RUT.
    -- --------------------------------------------------------

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE u.rut = BTRIM(p_rut)
          AND u.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'RUT_EXISTS'
        );
    END IF;


    -- --------------------------------------------------------
    -- Duplicado por correo
    -- --------------------------------------------------------
    --
    -- Solo usuarios NO eliminados reservan el correo.
    -- Comparación case-insensitive.
    -- --------------------------------------------------------

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE LOWER(u.email) = LOWER(BTRIM(p_email))
          AND u.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'EMAIL_EXISTS'
        );
    END IF;


    -- --------------------------------------------------------
    -- Perfil + auditoría
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
$function$;


-- ============================================================
-- SEGURIDAD DE EJECUCIÓN
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
'Crea un usuario funcional y registra auditoría de forma atómica. '
'RUT y correo solo deben ser únicos entre usuarios no eliminados.';


COMMIT;