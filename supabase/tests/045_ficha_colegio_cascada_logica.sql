-- HuellAPP · Regresión transaccional de la cascada lógica 045.
-- Ejecutar en DEV/QA después de 045, con SUPERADMIN, colegio, nivel y REUNION activos. Se crean fixtures aislados y se revierte todo.
BEGIN;
CREATE FUNCTION public.test_045_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.action = 'DELETE_ROOM' THEN RAISE EXCEPTION 'TEST_045_AUDIT_FAILURE'; END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    v_level record;
    v_activity uuid;
    v_actor uuid;
    v_role uuid;
    v_school public.colegios%ROWTYPE;
    v_course public.cursos_colegio%ROWTYPE;
    v_room public.salas%ROWTYPE;
    v_assignment public.asignaciones%ROWTYPE;
    v_historical uuid;
    v_cancelled uuid;
    v_contact uuid := gen_random_uuid();
    v_inactive uuid := gen_random_uuid();
    v_archived uuid := gen_random_uuid();
    v_request uuid := gen_random_uuid();
    v_pending_state uuid;
    v_cancelled_state uuid;
    v_original_school uuid;
    v_result jsonb;
    v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date;
BEGIN
    SELECT u.id, u.rol_id INTO v_actor, v_role FROM public.usuarios u JOIN public.roles r ON r.id = u.rol_id
    WHERE r.codigo = 'SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Falta SUPERADMIN activo'; END IF;
    -- Solo requiere maestros reales: colegio, nivel y tipo REUNION activos.
    -- Se crean todos los recursos y asignaciones necesarios dentro de ROLLBACK.
    SELECT * INTO v_school FROM public.colegios WHERE activo AND deleted_at IS NULL ORDER BY id LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Falta colegio activo para copiar su ubicación en el fixture'; END IF;
    SELECT id, nombre INTO v_level FROM public.niveles_curso WHERE activo ORDER BY orden LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Falta nivel de curso activo en los datos maestros'; END IF;
    SELECT id INTO v_activity FROM public.tipos_actividad WHERE codigo = 'REUNION' AND activo;
    IF NOT FOUND THEN RAISE EXCEPTION 'Falta tipo de actividad REUNION activo'; END IF;
    SELECT id INTO v_pending_state FROM public.estados_asignacion WHERE codigo = 'PENDIENTE' AND activo;
    SELECT id INTO v_cancelled_state FROM public.estados_asignacion WHERE codigo = 'CANCELADA' AND activo;
    IF v_pending_state IS NULL OR v_cancelled_state IS NULL THEN RAISE EXCEPTION 'Faltan estados PENDIENTE/CANCELADA activos'; END IF;
    v_original_school := v_school.id;
    v_school.id := gen_random_uuid();
    -- RBD de prueba de 20 caracteres, compatible con varchar(20) remoto.
    v_school.rbd := 'T045' || left(replace(v_school.id::text, '-', ''), 16);
    v_school.nombre := 'TEST 045 aislado';
    v_school.created_by := v_actor;
    INSERT INTO public.colegios SELECT v_school.*;
    INSERT INTO public.cursos_colegio (colegio_id, nivel_curso_id, seccion, nombre_mostrado, anio, created_by)
    VALUES (v_school.id, v_level.id, 'A', v_level.nombre || ' A', EXTRACT(YEAR FROM v_today)::integer, v_actor)
    RETURNING * INTO v_course;
    INSERT INTO public.salas (colegio_id, nombre, created_by)
    VALUES (v_school.id, 'TEST 045 sala', v_actor) RETURNING * INTO v_room;
    
    -- REUNION admite curso y sala, sin ramo ni espacios académicos.
    v_assignment.tipo_actividad_id := v_activity;
    v_assignment.colegio_id := v_school.id;
    v_assignment.hora_inicio := '09:00'::time;
    v_assignment.hora_fin := '10:00'::time;
    v_assignment.created_at := CURRENT_TIMESTAMP;
    v_assignment.updated_at := CURRENT_TIMESTAMP;

    INSERT INTO public.contactos_colegio (id, colegio_id, nombre, email, telefono, created_by)
    VALUES (v_contact, v_school.id, 'Contacto prueba', 'test045@example.org', '123456789', v_actor);
    INSERT INTO public.contactos_colegio (id, colegio_id, nombre, email, telefono, activo, created_by)
    VALUES (v_inactive, v_school.id, 'Contacto inactivo', 'test045inactive@example.org', '123456789', false, v_actor);
    INSERT INTO public.contactos_colegio (id, colegio_id, nombre, email, telefono, activo, deleted_at, created_by)
    VALUES (v_archived, v_school.id, 'Contacto ya eliminado', 'test045archived@example.org', '123456789', false, CURRENT_TIMESTAMP, v_actor);

    -- No trasladar recursos entre establecimientos: conserva su pertenencia histórica.
    BEGIN
        UPDATE public.cursos_colegio SET colegio_id = v_original_school WHERE id = v_course.id;
        RAISE EXCEPTION 'Se esperaba pertenencia inmutable';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'RESOURCE_SCHOOL_IMMUTABLE' THEN RAISE; END IF;
    END;
    -- La autoridad de la cascada es DELETE_SCHOOL, no permisos del cliente.
    DELETE FROM public.rol_permiso WHERE rol_id = v_role
      AND permiso_id IN (SELECT id FROM public.permisos WHERE codigo = 'DELETE_SCHOOL');
    v_result := public.eliminar_colegio_atomico(v_school.id, v_actor);
    ASSERT v_result->>'error_code' = 'FORBIDDEN';
    INSERT INTO public.rol_permiso (rol_id, permiso_id)
    SELECT v_role, id FROM public.permisos WHERE codigo = 'DELETE_SCHOOL';

    v_assignment.id := gen_random_uuid(); v_assignment.colegio_id := v_school.id;
    v_assignment.curso_colegio_id := v_course.id; v_assignment.sala_id := v_room.id;
    v_assignment.fecha := v_today; v_assignment.estado_id := v_pending_state;
    v_assignment.activo := true; v_assignment.deleted_at := NULL; v_assignment.created_by := v_actor;
    INSERT INTO public.asignaciones SELECT v_assignment.*;
    v_historical := v_assignment.id;
    INSERT INTO public.asignacion_contactos (asignacion_id, contacto_colegio_id, created_by)
    VALUES (v_historical, v_contact, v_actor);
    v_result := public.eliminar_colegio_atomico(v_school.id, v_actor);
    ASSERT v_result->>'error_code' = 'SCHOOL_HAS_FUTURE_ASSIGNMENTS';
    ASSERT (SELECT deleted_at IS NULL FROM public.colegios WHERE id = v_school.id);
    ASSERT NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE entity_id = v_school.id AND action = 'DELETE_SCHOOL');
    UPDATE public.asignaciones SET fecha = v_today - 1 WHERE id = v_historical;

    v_assignment.id := gen_random_uuid(); v_assignment.fecha := v_today + 1;
    INSERT INTO public.asignaciones SELECT v_assignment.*;
    v_cancelled := v_assignment.id;
    UPDATE public.asignaciones SET estado_id = v_cancelled_state WHERE id = v_cancelled;
    -- Cancelar no cambia activo: aun así debe liberar el bloqueo de eliminación.
    ASSERT (SELECT activo FROM public.asignaciones WHERE id = v_cancelled);

    CREATE TRIGGER test_045_audit BEFORE INSERT ON public.audit_logs
    FOR EACH ROW EXECUTE FUNCTION public.test_045_fail_audit();
    BEGIN
        PERFORM public.eliminar_colegio_atomico(v_school.id, v_actor);
        RAISE EXCEPTION 'Se esperaba fallo de auditoría de sala';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'TEST_045_AUDIT_FAILURE' THEN RAISE; END IF;
    END;
    -- Se revierten el colegio, los cursos ya procesados y sus audit_logs.
    ASSERT (SELECT deleted_at IS NULL AND activo FROM public.colegios WHERE id = v_school.id);
    ASSERT (SELECT deleted_at IS NULL AND activo FROM public.cursos_colegio WHERE id = v_course.id);
    ASSERT (SELECT deleted_at IS NULL AND activo FROM public.salas WHERE id = v_room.id);
    ASSERT (SELECT deleted_at IS NULL FROM public.contactos_colegio WHERE id = v_contact);
    ASSERT NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE entity_id IN (v_school.id, v_course.id, v_room.id, v_contact)
        AND action IN ('DELETE_SCHOOL', 'DELETE_COURSE', 'DELETE_ROOM', 'DELETE_SCHOOL_CONTACT'));
    DROP TRIGGER test_045_audit ON public.audit_logs;

    v_result := public.eliminar_colegio_atomico(v_school.id, v_actor, v_request, '127.0.0.1', 'test045');
    ASSERT v_result->>'ok' = 'true';
    ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by = v_actor FROM public.colegios WHERE id = v_school.id);
    ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by = v_actor FROM public.cursos_colegio WHERE id = v_course.id);
    ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by = v_actor FROM public.salas WHERE id = v_room.id);
    ASSERT (SELECT count(*) = 2 FROM public.contactos_colegio WHERE id IN (v_contact, v_inactive)
        AND NOT activo AND deleted_at IS NOT NULL AND updated_by = v_actor);
    ASSERT (SELECT count(*) = 5 FROM public.audit_logs WHERE request_id = v_request
        AND actor_user_id = v_actor AND ip_address = '127.0.0.1' AND user_agent = 'test045'
        AND old_values->>'deleted_at' IS NULL AND new_values->>'deleted_at' IS NOT NULL);
    ASSERT (SELECT new_values->'cascada'->'curso_ids' @> jsonb_build_array(v_course.id)
        FROM public.audit_logs WHERE request_id = v_request AND action = 'DELETE_SCHOOL');
    ASSERT NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE request_id = v_request AND entity_id = v_archived);
    ASSERT (SELECT count(*) = 2 FROM public.asignaciones WHERE id IN (v_historical, v_cancelled));
    ASSERT EXISTS (SELECT 1 FROM public.asignacion_contactos WHERE asignacion_id = v_historical AND contacto_colegio_id = v_contact);
    UPDATE public.asignaciones SET observacion = 'Historial intacto' WHERE id = v_historical;

    BEGIN
        UPDATE public.asignaciones SET estado_id = v_pending_state WHERE id = v_cancelled;
        RAISE EXCEPTION 'Se esperaba bloqueo de reapertura';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'ASSIGNMENT_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    BEGIN
        INSERT INTO public.salas (colegio_id, nombre, created_by) VALUES (v_school.id, 'Sala posterior', v_actor);
        RAISE EXCEPTION 'Se esperaba rechazo de nuevo hijo';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'SCHOOL_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    BEGIN
        UPDATE public.cursos_colegio SET activo = true WHERE id = v_course.id;
        RAISE EXCEPTION 'Se esperaba rechazo de reactivación de hijo';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'SCHOOL_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    v_result := public.eliminar_colegio_atomico(v_school.id, v_actor);
    ASSERT v_result->>'error_code' = 'SCHOOL_NOT_FOUND';
    RAISE NOTICE '045: cascada, permisos, rollback, historial y protección de reapertura aprobados';
END;
$$;
ROLLBACK;
