-- ============================================================
-- HuellAPP · Migración 045 · Ficha del colegio y cascada lógica
-- ============================================================
-- Aplicar después de 044 en DEV/QA antes de desplegar la nueva ficha.
-- REGLAS:
-- - Conserva contratos, tablas, FK, unicidad y permisos existentes.
-- - DELETE_SCHOOL autoriza la cascada; no exige permisos individuales de hijos.
-- - Colegio y cada hijo no eliminado reciben auditoría en la misma transacción.
-- - Canceladas/finalizadas no bloquean; su reapertura con recursos borrados falla.
-- - La fecha operativa se calcula explícitamente en America/Santiago.
-- - No borra ni reescribe asignaciones, participaciones ni sus contactos históricos.
-- - La pertenencia de Cursos/Salas/Contactos es inmutable para preservar referencias.
BEGIN;

/* ============================================================
   PROTECCIÓN DE HIJOS DEL COLEGIO
   ============================================================ */
CREATE OR REPLACE FUNCTION public.proteger_hijo_colegio()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_parent record;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.colegio_id IS DISTINCT FROM OLD.colegio_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'RESOURCE_SCHOOL_IMMUTABLE';
        END IF;
        IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'SCHOOL_RESOURCE_UNAVAILABLE';
        END IF;
        -- La cascada y la eliminación individual pueden archivar hijos sin
        -- revalidar un padre que se está eliminando en la misma transacción.
        IF NEW.deleted_at IS NOT NULL AND NEW.activo = false THEN RETURN NEW; END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- El bloqueo de padre serializa nuevas altas con DELETE_SCHOOL.
        SELECT activo, deleted_at INTO v_parent FROM public.colegios
        WHERE id = NEW.colegio_id FOR SHARE;
    ELSE
        -- Las RPC existentes ya bloquean el hijo antes de escribir. No tomar
        -- otro bloqueo de padre aquí evita invertir el orden padre/hijo de la
        -- cascada. Si la edición termina primero, la cascada la archiva después;
        -- si la cascada terminó primero, esta lectura rechaza el padre eliminado.
        SELECT activo, deleted_at INTO v_parent FROM public.colegios WHERE id = NEW.colegio_id;
    END IF;
    IF NOT FOUND OR v_parent.deleted_at IS NOT NULL
        OR (NEW.activo = true AND v_parent.activo IS NOT TRUE) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'SCHOOL_RESOURCE_UNAVAILABLE';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.proteger_hijo_colegio() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_proteger_hijo_colegio ON public.cursos_colegio;
CREATE TRIGGER trg_proteger_hijo_colegio BEFORE INSERT OR UPDATE ON public.cursos_colegio
FOR EACH ROW EXECUTE FUNCTION public.proteger_hijo_colegio();
DROP TRIGGER IF EXISTS trg_proteger_hijo_colegio ON public.salas;
CREATE TRIGGER trg_proteger_hijo_colegio BEFORE INSERT OR UPDATE ON public.salas
FOR EACH ROW EXECUTE FUNCTION public.proteger_hijo_colegio();
DROP TRIGGER IF EXISTS trg_proteger_hijo_colegio ON public.contactos_colegio;
CREATE TRIGGER trg_proteger_hijo_colegio BEFORE INSERT OR UPDATE ON public.contactos_colegio
FOR EACH ROW EXECUTE FUNCTION public.proteger_hijo_colegio();

/* ============================================================
   ELIMINACIÓN DEL COLEGIO Y AUDITORÍA POR CADA HIJO AFECTADO
   ============================================================ */
CREATE OR REPLACE FUNCTION public.eliminar_colegio_atomico(
    p_colegio_id uuid, p_actor_user_id uuid, p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL, p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor record;
    v_school record;
    v_config record;
    v_child record;
    v_old jsonb;
    v_new jsonb;
    v_affected jsonb := jsonb_build_object('curso_ids', '[]'::jsonb, 'sala_ids', '[]'::jsonb, 'contacto_ids', '[]'::jsonb);
BEGIN
    SELECT id, rol_id INTO v_actor FROM public.usuarios
    WHERE id = p_actor_user_id AND activo = true AND deleted_at IS NULL;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND'); END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id AND p.codigo = 'DELETE_SCHOOL' AND p.activo = true
    ) THEN RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN'); END IF;

    SELECT * INTO v_school FROM public.colegios WHERE id = p_colegio_id FOR UPDATE;
    IF NOT FOUND OR v_school.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;
    -- Incluye referencias a hijos para detectar también datos antiguos que no
    -- hubieran respetado el colegio_id de la asignación. No bloquea sus filas.
    IF EXISTS (
        SELECT 1 FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id = a.estado_id
        WHERE a.activo = true AND a.deleted_at IS NULL
          AND a.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
          AND e.codigo NOT IN ('CANCELADA', 'REALIZADA', 'NO_REALIZADA')
          AND (a.colegio_id = p_colegio_id
            OR EXISTS (SELECT 1 FROM public.cursos_colegio c WHERE c.id = a.curso_colegio_id AND c.colegio_id = p_colegio_id)
            OR EXISTS (SELECT 1 FROM public.salas s WHERE s.id = a.sala_id AND s.colegio_id = p_colegio_id)
            OR EXISTS (SELECT 1 FROM public.asignacion_contactos ac JOIN public.contactos_colegio c ON c.id = ac.contacto_colegio_id
                       WHERE ac.asignacion_id = a.id AND c.colegio_id = p_colegio_id))
    ) THEN RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_HAS_FUTURE_ASSIGNMENTS'); END IF;

    v_old := to_jsonb(v_school);
    UPDATE public.colegios SET activo = false, deleted_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id WHERE id = p_colegio_id;

    -- Las tres tablas son constantes de esta función, nunca entrada del cliente.
    -- El bucle comparte la auditoría y evita tres implementaciones de la cascada.
    FOR v_config IN SELECT * FROM (VALUES
        ('cursos_colegio', 'COURSE', 'DELETE_COURSE', 'curso_ids'),
        ('salas', 'ROOM', 'DELETE_ROOM', 'sala_ids'),
        ('contactos_colegio', 'SCHOOL_CONTACT', 'DELETE_SCHOOL_CONTACT', 'contacto_ids')
    ) AS config(table_name, entity_type, action, affected_key) LOOP
        FOR v_child IN EXECUTE format(
            'SELECT id, to_jsonb(t) AS snapshot FROM public.%I t WHERE colegio_id = $1 AND deleted_at IS NULL ORDER BY id FOR UPDATE',
            v_config.table_name
        ) USING p_colegio_id LOOP
            EXECUTE format(
                'UPDATE public.%I t SET activo = false, deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP, updated_by = $2 WHERE id = $1 RETURNING to_jsonb(t)',
                v_config.table_name
            ) INTO v_new USING v_child.id, p_actor_user_id;
            INSERT INTO public.audit_logs (
                actor_user_id, actor_role_id, action, entity_type, entity_id,
                old_values, new_values, description, request_id, ip_address, user_agent, source
            ) VALUES (
                p_actor_user_id, v_actor.rol_id, v_config.action, v_config.entity_type, v_child.id,
                v_child.snapshot, v_new, 'Eliminación lógica en cascada del colegio ' || p_colegio_id::text || '.',
                p_request_id, p_ip_address, p_user_agent, 'WEB'
            );
            v_affected := jsonb_set(v_affected, ARRAY[v_config.affected_key],
                (v_affected -> v_config.affected_key) || jsonb_build_array(v_child.id));
        END LOOP;
    END LOOP;
    SELECT to_jsonb(c) INTO v_new FROM public.colegios c WHERE id = p_colegio_id;
    INSERT INTO public.audit_logs (
        actor_user_id, actor_role_id, action, entity_type, entity_id,
        old_values, new_values, description, request_id, ip_address, user_agent, source
    ) VALUES (
        p_actor_user_id, v_actor.rol_id, 'DELETE_SCHOOL', 'SCHOOL', p_colegio_id,
        v_old, v_new || jsonb_build_object('cascada', v_affected), 'Eliminación lógica de colegio y sus recursos asociados.',
        p_request_id, p_ip_address, p_user_agent, 'WEB'
    );
    RETURN jsonb_build_object('ok', true, 'colegio_id', p_colegio_id);
END;
$$;
COMMENT ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text)
IS 'Elimina colegio, cursos, salas y contactos atómicamente, con auditoría por entidad e historial intacto.';
REVOKE ALL ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_colegio_atomico(uuid, uuid, uuid, inet, text) TO service_role;

/* ============================================================
   ASIGNACIONES: PADRE Y RECURSOS DISPONIBLES, INCLUSO AL REABRIR
   ============================================================ */
CREATE OR REPLACE FUNCTION public.proteger_recursos_asignacion()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_school public.colegios%ROWTYPE;
    v_course public.cursos_colegio%ROWTYPE;
    v_room public.salas%ROWTYPE;
    v_contact record;
    v_state text;
    v_validate boolean := true;
BEGIN
    SELECT codigo INTO v_state FROM public.estados_asignacion WHERE id = NEW.estado_id;
    IF TG_OP = 'UPDATE' THEN
        v_validate := NEW.curso_colegio_id IS DISTINCT FROM OLD.curso_colegio_id
            OR NEW.sala_id IS DISTINCT FROM OLD.sala_id OR NEW.colegio_id IS DISTINCT FROM OLD.colegio_id
            OR NEW.fecha IS DISTINCT FROM OLD.fecha OR (NEW.activo AND NOT OLD.activo)
            OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
            OR (NEW.estado_id IS DISTINCT FROM OLD.estado_id AND NEW.activo AND NEW.deleted_at IS NULL
                AND NEW.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
                AND v_state NOT IN ('CANCELADA', 'REALIZADA', 'NO_REALIZADA'));
    END IF;
    IF NOT v_validate THEN RETURN NEW; END IF;
    -- Orden fijo: colegio, curso, sala, contactos. SHARE se coordina con las
    -- RPC de eliminación. Las ediciones históricas sin cambios de contexto pasan.
    IF NEW.colegio_id IS NOT NULL THEN
        SELECT * INTO v_school FROM public.colegios WHERE id = NEW.colegio_id FOR SHARE;
        IF NOT FOUND OR NOT v_school.activo OR v_school.deleted_at IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
        END IF;
    END IF;
    IF NEW.curso_colegio_id IS NOT NULL THEN
        SELECT * INTO v_course FROM public.cursos_colegio WHERE id = NEW.curso_colegio_id FOR SHARE;
        IF NOT FOUND OR NOT v_course.activo OR v_course.deleted_at IS NOT NULL
            OR v_course.colegio_id IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
        END IF;
    END IF;
    IF NEW.sala_id IS NOT NULL THEN
        SELECT * INTO v_room FROM public.salas WHERE id = NEW.sala_id FOR SHARE;
        IF NOT FOUND OR NOT v_room.activo OR v_room.deleted_at IS NOT NULL
            OR v_room.colegio_id IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
        END IF;
    END IF;
    -- No valida contactos antiguos durante la edición general: la RPC 029
    -- puede reemplazarlos después de actualizar el contexto escolar. Cada
    -- referencia nueva se valida en validate_asignacion_contacto. Aquí se
    -- validan al reabrir/reactivar, cuando no se reemplazan los vínculos.
    IF TG_OP = 'UPDATE' AND v_state NOT IN ('CANCELADA', 'REALIZADA', 'NO_REALIZADA')
        AND (NEW.estado_id IS DISTINCT FROM OLD.estado_id
            OR (NEW.activo AND NOT OLD.activo)
            OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)) THEN
        FOR v_contact IN SELECT c.* FROM public.asignacion_contactos ac
            JOIN public.contactos_colegio c ON c.id = ac.contacto_colegio_id
            WHERE ac.asignacion_id = NEW.id ORDER BY c.id FOR SHARE OF c LOOP
            IF NOT v_contact.activo OR v_contact.deleted_at IS NOT NULL
                OR v_contact.colegio_id IS DISTINCT FROM NEW.colegio_id THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.proteger_recursos_asignacion() FROM PUBLIC, anon, authenticated;

/* El límite de dos contactos y los tipos admitidos se conservan. El bloqueo
   de la asignación serializa el conteo; padre/contacto no pueden borrarse
   mientras se incorpora una nueva referencia. */
CREATE OR REPLACE FUNCTION public.validate_asignacion_contacto()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_assignment record;
    v_school record;
    v_contact record;
    v_type text;
    v_count integer;
BEGIN
    SELECT * INTO v_assignment FROM public.asignaciones WHERE id = NEW.asignacion_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'La asignación indicada no existe.'; END IF;
    SELECT codigo INTO v_type FROM public.tipos_actividad WHERE id = v_assignment.tipo_actividad_id;
    IF v_type NOT IN ('ESPACIO_REFLEXION', 'ESPACIO_ENCUENTRO', 'REUNION') THEN
        RAISE EXCEPTION 'El tipo de actividad % no admite profesores/contactos.', v_type;
    END IF;
    SELECT activo, deleted_at INTO v_school FROM public.colegios WHERE id = v_assignment.colegio_id FOR SHARE;
    IF NOT FOUND OR NOT v_school.activo OR v_school.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
    END IF;
    SELECT * INTO v_contact FROM public.contactos_colegio WHERE id = NEW.contacto_colegio_id FOR SHARE;
    IF NOT FOUND OR NOT v_contact.activo OR v_contact.deleted_at IS NOT NULL
        OR v_contact.colegio_id IS DISTINCT FROM v_assignment.colegio_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
    END IF;
    SELECT count(*) INTO v_count FROM public.asignacion_contactos
    WHERE asignacion_id = NEW.asignacion_id AND id IS DISTINCT FROM NEW.id;
    IF v_count >= 2 THEN RAISE EXCEPTION 'Una asignación escolar admite como máximo 2 profesores/contactos.'; END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.validate_asignacion_contacto() FROM PUBLIC, anon, authenticated;

-- Las redefiniciones de eliminación individual y gestión de contactos que
-- siguen conservan los contratos 043/044 y ajustan solo la protección futura.

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
        SELECT 1 FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id = a.estado_id WHERE a.curso_colegio_id = p_curso_id
        AND a.activo = true AND a.deleted_at IS NULL
        AND e.codigo NOT IN ('CANCELADA', 'REALIZADA', 'NO_REALIZADA')
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
        SELECT 1 FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id = a.estado_id WHERE a.sala_id = p_sala_id
        AND a.activo = true AND a.deleted_at IS NULL
        AND e.codigo NOT IN ('CANCELADA', 'REALIZADA', 'NO_REALIZADA')
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

CREATE OR REPLACE FUNCTION public.gestionar_contacto_colegio_atomico(
    p_accion text,
    p_colegio_id uuid,
    p_contacto_id uuid,
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
    v_colegio record;
    v_contacto record;
    v_id uuid;
    v_permiso text;
    v_old jsonb;
    v_new jsonb;
    v_nombre text;
    v_email text;
    v_telefono text;
    v_rut text;
BEGIN
    /* Validación en la BD: no confiar únicamente en FastAPI. */
    v_permiso := CASE p_accion
      WHEN 'CREATE' THEN 'CREATE_SCHOOL_CONTACT'
      WHEN 'UPDATE' THEN 'UPDATE_SCHOOL_CONTACT'
      WHEN 'ACTIVATE' THEN 'UPDATE_SCHOOL_CONTACT'
      WHEN 'DEACTIVATE' THEN 'UPDATE_SCHOOL_CONTACT'
      WHEN 'DELETE' THEN 'DELETE_SCHOOL_CONTACT'
      ELSE NULL END;
    IF v_permiso IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_ACTION');
    END IF;

    SELECT u.id, u.rol_id INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id AND u.activo = true AND u.deleted_at IS NULL;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.rol_permiso rp
      JOIN public.permisos pe ON pe.id = rp.permiso_id
      WHERE rp.rol_id = v_actor.rol_id AND pe.codigo = v_permiso AND pe.activo = true
    ) THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT * INTO v_colegio FROM public.colegios
    WHERE id = p_colegio_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    IF p_accion = 'CREATE' THEN
      IF v_colegio.activo IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_INACTIVE');
      END IF;
      IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
      END IF;
      v_nombre := NULLIF(btrim(p_datos->>'nombre'), '');
      v_email := NULLIF(btrim(p_datos->>'email'), '');
      v_telefono := NULLIF(btrim(p_datos->>'telefono'), '');
      IF v_nombre IS NULL OR v_email IS NULL OR v_telefono IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'REQUIRED_FIELDS');
      END IF;
      INSERT INTO public.contactos_colegio (
        colegio_id, nombre, apellido_paterno, apellido_materno, rut,
        email, telefono, cargo, created_by, updated_by
      ) VALUES (
        p_colegio_id, v_nombre,
        NULLIF(btrim(p_datos->>'apellido_paterno'), ''),
        NULLIF(btrim(p_datos->>'apellido_materno'), ''),
        NULLIF(btrim(p_datos->>'rut'), ''),
        v_email, v_telefono, NULLIF(btrim(p_datos->>'cargo'), ''),
        p_actor_user_id, p_actor_user_id
      ) RETURNING id INTO v_id;
      v_old := NULL;
    ELSE
      IF p_contacto_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'CONTACT_NOT_FOUND');
      END IF;
      SELECT * INTO v_contacto FROM public.contactos_colegio
      WHERE id = p_contacto_id AND colegio_id = p_colegio_id FOR UPDATE;
      IF NOT FOUND OR v_contacto.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'CONTACT_NOT_FOUND');
      END IF;
      v_id := v_contacto.id;
      v_old := to_jsonb(v_contacto);

      IF p_accion IN ('CREATE','UPDATE','ACTIVATE') AND v_colegio.activo IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_INACTIVE');
      END IF;
      IF p_accion IN ('DEACTIVATE','DELETE') AND EXISTS (
        SELECT 1 FROM public.asignacion_contactos ac
        JOIN public.asignaciones a ON a.id = ac.asignacion_id
        JOIN public.estados_asignacion e ON e.id = a.estado_id
        WHERE ac.contacto_colegio_id = v_id
          AND a.activo = true AND a.deleted_at IS NULL
          AND a.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
          AND e.codigo NOT IN ('CANCELADA', 'REALIZADA', 'NO_REALIZADA')
      ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'CONTACT_HAS_FUTURE_ASSIGNMENTS');
      END IF;

      IF p_accion = 'UPDATE' THEN
        IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object'
           OR p_datos ? 'id' OR p_datos ? 'colegio_id'
           OR p_datos ? 'activo' OR p_datos ? 'deleted_at' THEN
          RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
        END IF;
        v_nombre := CASE WHEN p_datos ? 'nombre' THEN NULLIF(btrim(p_datos->>'nombre'), '') ELSE v_contacto.nombre END;
        v_email := CASE WHEN p_datos ? 'email' THEN NULLIF(btrim(p_datos->>'email'), '') ELSE v_contacto.email END;
        v_telefono := CASE WHEN p_datos ? 'telefono' THEN NULLIF(btrim(p_datos->>'telefono'), '') ELSE v_contacto.telefono END;
        IF v_nombre IS NULL OR v_email IS NULL OR v_telefono IS NULL THEN
          RETURN jsonb_build_object('ok', false, 'error_code', 'REQUIRED_FIELDS');
        END IF;
        UPDATE public.contactos_colegio SET
          nombre = v_nombre,
          apellido_paterno = CASE WHEN p_datos ? 'apellido_paterno' THEN NULLIF(btrim(p_datos->>'apellido_paterno'), '') ELSE apellido_paterno END,
          apellido_materno = CASE WHEN p_datos ? 'apellido_materno' THEN NULLIF(btrim(p_datos->>'apellido_materno'), '') ELSE apellido_materno END,
          rut = CASE WHEN p_datos ? 'rut' THEN NULLIF(btrim(p_datos->>'rut'), '') ELSE rut END,
          email = v_email, telefono = v_telefono,
          cargo = CASE WHEN p_datos ? 'cargo' THEN NULLIF(btrim(p_datos->>'cargo'), '') ELSE cargo END,
          updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      ELSIF p_accion = 'ACTIVATE' THEN
        UPDATE public.contactos_colegio
        SET activo = true, updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      ELSIF p_accion = 'DEACTIVATE' THEN
        UPDATE public.contactos_colegio
        SET activo = false, updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      ELSIF p_accion = 'DELETE' THEN
        UPDATE public.contactos_colegio
        SET activo = false, deleted_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      END IF;
    END IF;

    SELECT to_jsonb(c) INTO v_new FROM public.contactos_colegio c WHERE c.id = v_id;
    INSERT INTO public.audit_logs (
      actor_user_id, actor_role_id, action, entity_type, entity_id,
      old_values, new_values, description, request_id, ip_address, user_agent, source
    ) VALUES (
      p_actor_user_id, v_actor.rol_id, p_accion || '_SCHOOL_CONTACT',
      'SCHOOL_CONTACT', v_id, v_old, v_new,
      'Operación sobre contacto de colegio.', p_request_id, p_ip_address, p_user_agent, 'WEB'
    );
    RETURN jsonb_build_object('ok', true, 'contacto_id', v_id);
END;
$$;
REVOKE ALL ON FUNCTION public.gestionar_contacto_colegio_atomico(text, uuid, uuid, jsonb, uuid, uuid, inet, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gestionar_contacto_colegio_atomico(text, uuid, uuid, jsonb, uuid, uuid, inet, text) TO service_role;

COMMIT;
