-- ============================================================
-- HuellAPP
-- Migración 039
-- Evitar UPDATE_USER sin cambios efectivos
-- ============================================================

BEGIN;


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
AS $function$
DECLARE
    v_actor record;
    v_target record;
    v_old_values jsonb;
    v_new_values jsonb;

    v_nombres text;
    v_apellido_paterno text;
    v_apellido_materno text;
    v_telefono text;
BEGIN
    -- --------------------------------------------------------
    -- Actor
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
    -- Validación del payload
    -- --------------------------------------------------------

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
        (
            p_cambios ? 'nombres'
            AND NULLIF(
                BTRIM(p_cambios ->> 'nombres'),
                ''
            ) IS NULL
        )
        OR
        (
            p_cambios ? 'apellido_paterno'
            AND NULLIF(
                BTRIM(p_cambios ->> 'apellido_paterno'),
                ''
            ) IS NULL
        )
        OR
        (
            p_cambios ? 'apellido_materno'
            AND NULLIF(
                BTRIM(p_cambios ->> 'apellido_materno'),
                ''
            ) IS NULL
        )
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_REQUIRED_FIELD'
        );
    END IF;


    -- --------------------------------------------------------
    -- Calcular estado resultante ANTES del UPDATE
    -- --------------------------------------------------------

    v_nombres :=
        CASE
            WHEN p_cambios ? 'nombres'
                THEN BTRIM(p_cambios ->> 'nombres')
            ELSE v_target.nombres
        END;

    v_apellido_paterno :=
        CASE
            WHEN p_cambios ? 'apellido_paterno'
                THEN BTRIM(
                    p_cambios ->> 'apellido_paterno'
                )
            ELSE v_target.apellido_paterno
        END;

    v_apellido_materno :=
        CASE
            WHEN p_cambios ? 'apellido_materno'
                THEN BTRIM(
                    p_cambios ->> 'apellido_materno'
                )
            ELSE v_target.apellido_materno
        END;

    v_telefono :=
        CASE
            WHEN p_cambios ? 'telefono'
                THEN NULLIF(
                    BTRIM(p_cambios ->> 'telefono'),
                    ''
                )
            ELSE v_target.telefono
        END;


    -- --------------------------------------------------------
    -- Evitar actualización sin cambios efectivos
    -- --------------------------------------------------------

    IF v_nombres IS NOT DISTINCT FROM v_target.nombres
       AND v_apellido_paterno
           IS NOT DISTINCT FROM v_target.apellido_paterno
       AND v_apellido_materno
           IS NOT DISTINCT FROM v_target.apellido_materno
       AND v_telefono
           IS NOT DISTINCT FROM v_target.telefono THEN

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NO_EFFECTIVE_CHANGES'
        );
    END IF;


    -- --------------------------------------------------------
    -- Valores anteriores
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Actualización
    -- --------------------------------------------------------

    UPDATE public.usuarios
    SET
        nombres = v_nombres,
        apellido_paterno = v_apellido_paterno,
        apellido_materno = v_apellido_materno,
        telefono = v_telefono,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;


    -- --------------------------------------------------------
    -- Valores nuevos
    -- --------------------------------------------------------

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
$function$;


-- ============================================================
-- SEGURIDAD
-- ============================================================

REVOKE ALL ON FUNCTION public.actualizar_usuario_atomico(
    uuid,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.actualizar_usuario_atomico(
    uuid,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.actualizar_usuario_atomico(
    uuid,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.actualizar_usuario_atomico(
    uuid,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMENT ON FUNCTION public.actualizar_usuario_atomico(
    uuid,
    jsonb,
    uuid,
    uuid,
    inet,
    text
) IS
'Actualiza datos básicos de un usuario solo cuando existen cambios efectivos y registra auditoría en una sola transacción.';


COMMIT;