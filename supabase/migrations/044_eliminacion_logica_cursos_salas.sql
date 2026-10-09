-- 044: Eliminación lógica auditada de cursos y salas.
-- Aplicar después de 043. Conserva FK, historial y unicidad existente.
BEGIN;

INSERT INTO public.permisos (codigo, nombre, descripcion, modulo, activo)
VALUES ('DELETE_COURSE', 'Eliminar cursos', 'Eliminación lógica auditada sin asignaciones futuras activas.', 'CURSOS', true)
ON CONFLICT (codigo) DO UPDATE SET activo = true;
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id FROM public.roles r JOIN public.permisos p ON p.codigo = 'DELETE_COURSE'
WHERE r.codigo = 'SUPERADMIN' ON CONFLICT (rol_id, permiso_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.eliminar_curso_atomico(
    p_curso_id uuid, p_actor_user_id uuid, p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL, p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor record;
    v_actual record;
    v_old jsonb;
    v_new jsonb;
BEGIN
    SELECT id, rol_id INTO v_actor FROM public.usuarios
    WHERE id = p_actor_user_id AND activo = true AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id AND p.codigo = 'DELETE_COURSE' AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;
    -- FOR UPDATE se coordina con FOR SHARE del trigger de asignaciones.
    SELECT * INTO v_actual FROM public.cursos_colegio WHERE id = p_curso_id FOR UPDATE;
    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_NOT_FOUND');
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.asignaciones a WHERE a.curso_colegio_id = p_curso_id
        AND a.activo = true AND a.deleted_at IS NULL
        AND a.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COURSE_HAS_FUTURE_ASSIGNMENTS');
    END IF;
    v_old := public.snapshot_curso_auditoria(p_curso_id)
        || jsonb_build_object('deleted_at', v_actual.deleted_at, 'updated_by', v_actual.updated_by);
    UPDATE public.cursos_colegio SET activo = false, deleted_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id WHERE id = p_curso_id;
    v_new := public.snapshot_curso_auditoria(p_curso_id)
        || jsonb_build_object('deleted_at', CURRENT_TIMESTAMP, 'updated_by', p_actor_user_id);
    INSERT INTO public.audit_logs (
        actor_user_id, actor_role_id, action, entity_type, entity_id,
        old_values, new_values, description, request_id, ip_address, user_agent, source
    ) VALUES (
        p_actor_user_id, v_actor.rol_id, 'DELETE_COURSE', 'COURSE', p_curso_id,
        v_old, v_new, 'Eliminación lógica de curso.', p_request_id, p_ip_address, p_user_agent, 'WEB'
    );
    RETURN jsonb_build_object('ok', true, 'curso_id', p_curso_id);
END;
$$;
REVOKE ALL ON FUNCTION public.eliminar_curso_atomico(uuid, uuid, uuid, inet, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_curso_atomico(uuid, uuid, uuid, inet, text) TO service_role;

INSERT INTO public.permisos (codigo, nombre, descripcion, modulo, activo)
VALUES ('DELETE_ROOM', 'Eliminar salas', 'Eliminación lógica auditada sin asignaciones futuras activas.', 'SALAS', true)
ON CONFLICT (codigo) DO UPDATE SET activo = true;
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id FROM public.roles r JOIN public.permisos p ON p.codigo = 'DELETE_ROOM'
WHERE r.codigo = 'SUPERADMIN' ON CONFLICT (rol_id, permiso_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.eliminar_sala_atomica(
    p_sala_id uuid, p_actor_user_id uuid, p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL, p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor record;
    v_actual record;
    v_old jsonb;
    v_new jsonb;
BEGIN
    SELECT id, rol_id INTO v_actor FROM public.usuarios
    WHERE id = p_actor_user_id AND activo = true AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id AND p.codigo = 'DELETE_ROOM' AND p.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;
    -- FOR UPDATE se coordina con FOR SHARE del trigger de asignaciones.
    SELECT * INTO v_actual FROM public.salas WHERE id = p_sala_id FOR UPDATE;
    IF NOT FOUND OR v_actual.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_NOT_FOUND');
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.asignaciones a WHERE a.sala_id = p_sala_id
        AND a.activo = true AND a.deleted_at IS NULL
        AND a.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ROOM_HAS_FUTURE_ASSIGNMENTS');
    END IF;
    v_old := public.snapshot_sala_auditoria(p_sala_id)
        || jsonb_build_object('deleted_at', v_actual.deleted_at, 'updated_by', v_actual.updated_by);
    UPDATE public.salas SET activo = false, deleted_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id WHERE id = p_sala_id;
    v_new := public.snapshot_sala_auditoria(p_sala_id)
        || jsonb_build_object('deleted_at', CURRENT_TIMESTAMP, 'updated_by', p_actor_user_id);
    INSERT INTO public.audit_logs (
        actor_user_id, actor_role_id, action, entity_type, entity_id,
        old_values, new_values, description, request_id, ip_address, user_agent, source
    ) VALUES (
        p_actor_user_id, v_actor.rol_id, 'DELETE_ROOM', 'ROOM', p_sala_id,
        v_old, v_new, 'Eliminación lógica de sala.', p_request_id, p_ip_address, p_user_agent, 'WEB'
    );
    RETURN jsonb_build_object('ok', true, 'sala_id', p_sala_id);
END;
$$;
REVOKE ALL ON FUNCTION public.eliminar_sala_atomica(uuid, uuid, uuid, inet, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_sala_atomica(uuid, uuid, uuid, inet, text) TO service_role;

-- Valida nuevas referencias incluso en fechas pasadas. En actualizaciones
-- históricas conserva referencias intactas, salvo reactivación/reprogramación.
CREATE OR REPLACE FUNCTION public.proteger_recursos_asignacion()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_curso public.cursos_colegio%ROWTYPE;
    v_sala public.salas%ROWTYPE;
    v_validar boolean := true;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_validar := NEW.curso_colegio_id IS DISTINCT FROM OLD.curso_colegio_id
            OR NEW.sala_id IS DISTINCT FROM OLD.sala_id
            OR NEW.colegio_id IS DISTINCT FROM OLD.colegio_id
            OR NEW.fecha IS DISTINCT FROM OLD.fecha
            OR (NEW.activo AND NOT OLD.activo)
            OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
            OR (NEW.estado_id IS DISTINCT FROM OLD.estado_id
                AND NEW.activo AND NEW.deleted_at IS NULL
                AND NEW.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date);
    END IF;
    IF NOT v_validar THEN RETURN NEW; END IF;
    -- Orden fijo: curso, sala. SHARE entra en conflicto con la eliminación,
    -- pero permite que varias asignaciones usen el mismo recurso.
    IF NEW.curso_colegio_id IS NOT NULL THEN
        SELECT * INTO v_curso FROM public.cursos_colegio
        WHERE id = NEW.curso_colegio_id FOR SHARE;
        IF NOT FOUND OR v_curso.deleted_at IS NOT NULL OR NOT v_curso.activo
            OR v_curso.colegio_id IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
        END IF;
    END IF;
    IF NEW.sala_id IS NOT NULL THEN
        SELECT * INTO v_sala FROM public.salas WHERE id = NEW.sala_id FOR SHARE;
        IF NOT FOUND OR v_sala.deleted_at IS NOT NULL OR NOT v_sala.activo
            OR v_sala.colegio_id IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.proteger_recursos_asignacion() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_proteger_recursos_asignacion ON public.asignaciones;
CREATE TRIGGER trg_proteger_recursos_asignacion BEFORE INSERT OR UPDATE
ON public.asignaciones FOR EACH ROW EXECUTE FUNCTION public.proteger_recursos_asignacion();
COMMIT;
