-- ============================================================
-- HuellAPP
-- Migración 033
-- Atomicidad de gestión de cursos
-- ============================================================
--
-- Flujos migrados:
-- - crear curso;
-- - actualizar curso;
-- - activar curso;
-- - desactivar curso.
--
-- La modificación del curso y su audit_log quedan dentro de la
-- misma transacción PostgreSQL.
-- ============================================================

BEGIN;


-- ============================================================
-- SNAPSHOT INTERNO PARA AUDITORÍA
-- ============================================================

CREATE OR REPLACE FUNCTION public.snapshot_curso_auditoria(
    p_curso_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'id', cc.id,
        'colegio_id', cc.colegio_id,
        'nivel_curso_id', cc.nivel_curso_id,
        'seccion', cc.seccion,
        'nombre_mostrado', cc.nombre_mostrado,
        'anio', cc.anio,
        'activo', cc.activo,
        'created_at', cc.created_at,
        'updated_at', cc.updated_at
    )
    FROM public.cursos_colegio cc
    WHERE cc.id = p_curso_id;
$$;


-- ============================================================
-- CREAR CURSO
-- ============================================================

CREATE OR REPLACE FUNCTION public.crear_curso_atomico(
    p_colegio_id uuid,
    p_nivel_curso_id uuid,
    p_seccion text,
    p_anio integer,
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
    v_nivel record;
    v_curso_id uuid;
    v_seccion text;
    v_nombre_mostrado text;
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
          AND p.codigo = 'CREATE_COURSE'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    v_seccion := UPPER(BTRIM(p_seccion));

    IF v_seccion !~ '^[A-Z]$' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_SECTION');
    END IF;

    IF p_anio < 2000 OR p_anio > 2100 THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_YEAR');
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

    SELECT nc.id, nc.nombre
    INTO v_nivel
    FROM public.niveles_curso nc
    WHERE nc.id = p_nivel_curso_id
      AND nc.activo = true;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'LEVEL_NOT_ACTIVE');
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.cursos_colegio cc
        WHERE cc.colegio_id = p_colegio_id
          AND cc.nivel_curso_id = p_nivel_curso_id
          AND cc.seccion = v_seccion
          AND cc.anio = p_anio
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_EXISTS');
    END IF;

    v_nombre_mostrado := v_nivel.nombre || ' ' || v_seccion;

    BEGIN
        INSERT INTO public.cursos_colegio (
            colegio_id,
            nivel_curso_id,
            seccion,
            nombre_mostrado,
            anio,
            activo,
            created_by,
            updated_by
        )
        VALUES (
            p_colegio_id,
            p_nivel_curso_id,
            v_seccion,
            v_nombre_mostrado,
            p_anio,
            true,
            p_actor_user_id,
            p_actor_user_id
        )
        RETURNING id INTO v_curso_id;

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_EXISTS');
    END;

    v_new_values := public.snapshot_curso_auditoria(v_curso_id);

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
        'CREATE_COURSE',
        'COURSE',
        v_curso_id,
        NULL,
        v_new_values,
        'Creación de curso.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object(
        'ok', true,
        'curso_id', v_curso_id
    );
END;
$$;


-- ============================================================
-- ACTUALIZAR CURSO
-- ============================================================

CREATE OR REPLACE FUNCTION public.actualizar_curso_atomico(
    p_curso_id uuid,
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
    v_nivel_curso_id uuid;
    v_nivel record;
    v_seccion text;
    v_anio integer;
    v_nombre_mostrado text;
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
          AND p.codigo = 'UPDATE_COURSE'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.cursos_colegio
    WHERE id = p_curso_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_NOT_FOUND');
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
            'nivel_curso_id',
            'seccion',
            'anio'
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

        v_nivel_curso_id := CASE
            WHEN p_cambios ? 'nivel_curso_id'
                THEN (p_cambios ->> 'nivel_curso_id')::uuid
            ELSE v_actual.nivel_curso_id
        END;

        v_anio := CASE
            WHEN p_cambios ? 'anio'
                THEN (p_cambios ->> 'anio')::integer
            ELSE v_actual.anio
        END;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
    END;

    v_seccion := CASE
        WHEN p_cambios ? 'seccion'
            THEN UPPER(BTRIM(p_cambios ->> 'seccion'))
        ELSE v_actual.seccion
    END;

    IF v_seccion !~ '^[A-Z]$' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_SECTION');
    END IF;

    IF v_anio < 2000 OR v_anio > 2100 THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_YEAR');
    END IF;

    -- Se conserva la semántica actual de la API:
    -- el colegio se revalida cuando cambia.
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

    -- El nivel se necesita siempre para recalcular nombre_mostrado
    -- cuando cambia nivel o sección, y debe estar activo en ese caso.
    IF (p_cambios ? 'nivel_curso_id') OR (p_cambios ? 'seccion') THEN
        SELECT nc.id, nc.nombre
        INTO v_nivel
        FROM public.niveles_curso nc
        WHERE nc.id = v_nivel_curso_id
          AND nc.activo = true;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'LEVEL_NOT_ACTIVE');
        END IF;

        v_nombre_mostrado := v_nivel.nombre || ' ' || v_seccion;
    ELSE
        v_nombre_mostrado := v_actual.nombre_mostrado;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.cursos_colegio cc
        WHERE cc.colegio_id = v_colegio_id
          AND cc.nivel_curso_id = v_nivel_curso_id
          AND cc.seccion = v_seccion
          AND cc.anio = v_anio
          AND cc.id <> p_curso_id
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_EXISTS');
    END IF;

    v_old_values := public.snapshot_curso_auditoria(p_curso_id);

    BEGIN
        UPDATE public.cursos_colegio
        SET
            colegio_id = v_colegio_id,
            nivel_curso_id = v_nivel_curso_id,
            seccion = v_seccion,
            nombre_mostrado = v_nombre_mostrado,
            anio = v_anio,
            updated_by = p_actor_user_id
        WHERE id = p_curso_id;

    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_EXISTS');
    END;

    v_new_values := public.snapshot_curso_auditoria(p_curso_id);

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
        'UPDATE_COURSE',
        'COURSE',
        p_curso_id,
        v_old_values,
        v_new_values,
        'Actualización de curso.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'curso_id', p_curso_id);
END;
$$;


-- ============================================================
-- ACTIVAR CURSO
-- ============================================================

CREATE OR REPLACE FUNCTION public.activar_curso_atomico(
    p_curso_id uuid,
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
          AND p.codigo = 'ACTIVATE_COURSE'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.cursos_colegio
    WHERE id = p_curso_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_NOT_FOUND');
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

    IF NOT EXISTS (
        SELECT 1
        FROM public.niveles_curso nc
        WHERE nc.id = v_actual.nivel_curso_id
          AND nc.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'LEVEL_NOT_ACTIVE');
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.cursos_colegio cc
        WHERE cc.colegio_id = v_actual.colegio_id
          AND cc.nivel_curso_id = v_actual.nivel_curso_id
          AND cc.seccion = v_actual.seccion
          AND cc.anio = v_actual.anio
          AND cc.id <> p_curso_id
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_EXISTS');
    END IF;

    UPDATE public.cursos_colegio
    SET
        activo = true,
        updated_by = p_actor_user_id
    WHERE id = p_curso_id;

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
        'ACTIVATE_COURSE',
        'COURSE',
        p_curso_id,
        jsonb_build_object('activo', false),
        jsonb_build_object('activo', true),
        'Activación de curso.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'curso_id', p_curso_id);
END;
$$;


-- ============================================================
-- DESACTIVAR CURSO
-- ============================================================

CREATE OR REPLACE FUNCTION public.desactivar_curso_atomico(
    p_curso_id uuid,
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
          AND p.codigo = 'DEACTIVATE_COURSE'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT *
    INTO v_actual
    FROM public.cursos_colegio
    WHERE id = p_curso_id
    FOR UPDATE;

    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_NOT_FOUND');
    END IF;

    IF v_actual.activo IS FALSE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ALREADY_INACTIVE');
    END IF;

    UPDATE public.cursos_colegio
    SET
        activo = false,
        updated_by = p_actor_user_id
    WHERE id = p_curso_id;

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
        'DEACTIVATE_COURSE',
        'COURSE',
        p_curso_id,
        jsonb_build_object('activo', true),
        jsonb_build_object('activo', false),
        'Desactivación de curso.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'curso_id', p_curso_id);
END;
$$;


-- ============================================================
-- COMENTARIOS
-- ============================================================

COMMENT ON FUNCTION public.crear_curso_atomico(
    uuid, uuid, text, integer, uuid, uuid, inet, text
) IS
'Crea un curso y registra CREATE_COURSE de forma atómica.';

COMMENT ON FUNCTION public.actualizar_curso_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) IS
'Actualiza un curso y registra UPDATE_COURSE de forma atómica.';

COMMENT ON FUNCTION public.activar_curso_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Activa un curso y registra ACTIVATE_COURSE de forma atómica.';

COMMENT ON FUNCTION public.desactivar_curso_atomico(
    uuid, uuid, uuid, inet, text
) IS
'Desactiva un curso y registra DEACTIVATE_COURSE de forma atómica.';


-- ============================================================
-- SEGURIDAD
-- ============================================================

REVOKE ALL ON FUNCTION public.snapshot_curso_auditoria(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.snapshot_curso_auditoria(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.snapshot_curso_auditoria(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.snapshot_curso_auditoria(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.crear_curso_atomico(
    uuid, uuid, text, integer, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crear_curso_atomico(
    uuid, uuid, text, integer, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.crear_curso_atomico(
    uuid, uuid, text, integer, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.crear_curso_atomico(
    uuid, uuid, text, integer, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.actualizar_curso_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.actualizar_curso_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.actualizar_curso_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_curso_atomico(
    uuid, jsonb, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.activar_curso_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activar_curso_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.activar_curso_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.activar_curso_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.desactivar_curso_atomico(
    uuid, uuid, uuid, inet, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.desactivar_curso_atomico(
    uuid, uuid, uuid, inet, text
) FROM anon;
REVOKE ALL ON FUNCTION public.desactivar_curso_atomico(
    uuid, uuid, uuid, inet, text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.desactivar_curso_atomico(
    uuid, uuid, uuid, inet, text
) TO service_role;


COMMIT;
