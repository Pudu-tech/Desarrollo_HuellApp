-- ============================================================
-- HuellAPP
-- Migración 040
-- Cambio controlado de correo de usuario
-- ============================================================

-- DOCUMENTACIÓN
-- La RPC registra el cambio en public.usuarios y auditoría.
-- FastAPI coordina por separado la actualización de Supabase Auth
-- y su restauración compensatoria si la operación funcional falla.
-- Documentación únicamente; no repetir la migración en Supabase.

BEGIN;


CREATE OR REPLACE FUNCTION public.cambiar_email_usuario_atomico(
    p_user_id uuid,
    p_new_email text,
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
    v_target record;
    v_new_email text;
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
    -- Permiso
    --
    -- Por ahora reutilizamos UPDATE_USER.
    -- El cambio de correo sigue siendo una operación separada,
    -- pero no introducimos todavía un permiso nuevo innecesario.
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Usuario objetivo
    -- --------------------------------------------------------

    SELECT
        u.id,
        u.email,
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


    -- --------------------------------------------------------
    -- Protección DIRECTIVA / SUPERADMIN
    -- --------------------------------------------------------

    IF (
        v_actor.role_code = 'DIRECTIVA'
        AND v_target.role_code = 'SUPERADMIN'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN_SUPERADMIN'
        );
    END IF;


    -- --------------------------------------------------------
    -- Normalización y validación mínima
    -- --------------------------------------------------------

    v_new_email := LOWER(
        BTRIM(
            COALESCE(p_new_email, '')
        )
    );

    IF v_new_email = '' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_EMAIL'
        );
    END IF;

    IF v_new_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_EMAIL'
        );
    END IF;


    -- --------------------------------------------------------
    -- Mismo correo
    -- --------------------------------------------------------

    IF LOWER(v_target.email) = v_new_email THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'SAME_EMAIL'
        );
    END IF;


    -- --------------------------------------------------------
    -- Correo ocupado por otro usuario NO eliminado
    --
    -- Los usuarios eliminados no reservan el correo.
    -- Esto coincide con las reglas implementadas previamente.
    -- --------------------------------------------------------

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE LOWER(u.email) = v_new_email
          AND u.deleted_at IS NULL
          AND u.id <> p_user_id
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'EMAIL_EXISTS'
        );
    END IF;


    -- --------------------------------------------------------
    -- Actualización
    -- --------------------------------------------------------

    UPDATE public.usuarios
    SET
        email = v_new_email,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;


    -- --------------------------------------------------------
    -- Auditoría
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
        'CHANGE_USER_EMAIL',
        'USER',
        p_user_id,
        jsonb_build_object(
            'email', v_target.email
        ),
        jsonb_build_object(
            'email', v_new_email
        ),
        'Cambio de correo electrónico de usuario.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    RETURN jsonb_build_object(
        'ok', true,
        'user_id', p_user_id,
        'old_email', v_target.email,
        'new_email', v_new_email
    );
END;
$function$;


-- ============================================================
-- SEGURIDAD DE EJECUCIÓN
-- ============================================================

REVOKE ALL ON FUNCTION public.cambiar_email_usuario_atomico(
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.cambiar_email_usuario_atomico(
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.cambiar_email_usuario_atomico(
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.cambiar_email_usuario_atomico(
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMENT ON FUNCTION public.cambiar_email_usuario_atomico(
    uuid,
    text,
    uuid,
    uuid,
    inet,
    text
) IS
'Cambia el correo de public.usuarios manteniendo el mismo UUID y registra CHANGE_USER_EMAIL en auditoría. Debe ser utilizada por el backend coordinadamente con Supabase Auth.';


COMMIT;