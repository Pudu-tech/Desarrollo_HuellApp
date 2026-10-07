-- Ejecutar en DEV/QA con migración 044 aplicada y datos maestros.
-- Requiere SUPERADMIN, colegio y nivel activos y tipo REUNION; no requiere asignaciones previas. Todas las pruebas se revierten con ROLLBACK.
BEGIN;

CREATE FUNCTION public.test_044_fail_audit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.action IN ('DELETE_COURSE', 'DELETE_ROOM') THEN
        RAISE EXCEPTION 'TEST_044_AUDIT_FAILURE';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    v_level record;
    v_activity uuid;
    v_school public.colegios%ROWTYPE;
    v_actor uuid;
    v_role uuid;
    v_course public.cursos_colegio%ROWTYPE;
    v_room public.salas%ROWTYPE;
    v_assignment public.asignaciones%ROWTYPE;
    v_result jsonb;
    v_id uuid;
    v_original_course uuid;
    v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date;
BEGIN
    SELECT u.id, u.rol_id INTO v_actor, v_role FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE r.codigo = 'SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Falta fixture SUPERADMIN activo'; END IF;

    -- Solo requiere maestros reales: colegio, nivel y tipo REUNION activos.
    -- Se crean todos los recursos y asignaciones necesarios dentro de ROLLBACK.
    SELECT * INTO v_school FROM public.colegios WHERE activo AND deleted_at IS NULL ORDER BY id LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Falta colegio activo para copiar su ubicación en el fixture'; END IF;
    SELECT id, nombre INTO v_level FROM public.niveles_curso WHERE activo ORDER BY orden LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Falta nivel de curso activo en los datos maestros'; END IF;
    SELECT id INTO v_activity FROM public.tipos_actividad WHERE codigo = 'REUNION' AND activo;
    IF NOT FOUND THEN RAISE EXCEPTION 'Falta tipo de actividad REUNION activo'; END IF;
    
    v_school.id := gen_random_uuid();
    -- RBD de prueba de 20 caracteres, compatible con varchar(20) remoto.
    v_school.rbd := 'T044' || left(replace(v_school.id::text, '-', ''), 16);
    v_school.nombre := 'TEST 044 aislado';
    v_school.created_by := v_actor;
    INSERT INTO public.colegios SELECT v_school.*;
    INSERT INTO public.cursos_colegio (colegio_id, nivel_curso_id, seccion, nombre_mostrado, anio, created_by)
    VALUES (v_school.id, v_level.id, 'A', v_level.nombre || ' A', EXTRACT(YEAR FROM v_today)::integer, v_actor)
    RETURNING * INTO v_course;
    INSERT INTO public.salas (colegio_id, nombre, created_by)
    VALUES (v_school.id, 'TEST 044 sala', v_actor) RETURNING * INTO v_room;
    INSERT INTO public.cursos_colegio (colegio_id, nivel_curso_id, seccion, nombre_mostrado, anio, created_by)
    VALUES (v_school.id, v_level.id, 'B', v_level.nombre || ' B', v_course.anio, v_actor)
    RETURNING id INTO v_original_course;
    -- REUNION admite curso y sala, sin ramo ni espacios académicos.
    v_assignment.tipo_actividad_id := v_activity;
    v_assignment.colegio_id := v_school.id;
    v_assignment.hora_inicio := '09:00'::time;
    v_assignment.hora_fin := '10:00'::time;
    v_assignment.created_at := CURRENT_TIMESTAMP;
    v_assignment.updated_at := CURRENT_TIMESTAMP;

    -- Permisos efectivos, tanto para cursos como para salas.
    DELETE FROM public.rol_permiso WHERE rol_id = v_role
    AND permiso_id IN (SELECT id FROM public.permisos WHERE codigo IN ('DELETE_COURSE', 'DELETE_ROOM'));
    v_result := public.eliminar_curso_atomico(v_course.id, v_actor);
    ASSERT v_result->>'error_code' = 'FORBIDDEN', 'Curso debe exigir permiso';
    v_result := public.eliminar_sala_atomica(v_room.id, v_actor);
    ASSERT v_result->>'error_code' = 'FORBIDDEN', 'Sala debe exigir permiso';
    INSERT INTO public.rol_permiso (rol_id, permiso_id)
    SELECT v_role, id FROM public.permisos WHERE codigo IN ('DELETE_COURSE', 'DELETE_ROOM');
    v_result := public.eliminar_curso_atomico(v_course.id, gen_random_uuid());
    ASSERT v_result->>'error_code' = 'ACTOR_NOT_FOUND', 'Actor inválido';

    -- Una asignación de hoy bloquea ambos recursos.
    v_assignment.id := gen_random_uuid();
    v_assignment.curso_colegio_id := v_course.id;
    v_assignment.sala_id := v_room.id;
    v_assignment.fecha := v_today;
    v_assignment.activo := true;
    v_assignment.deleted_at := NULL;
    v_assignment.created_by := v_actor;
    SELECT id INTO v_assignment.estado_id FROM public.estados_asignacion WHERE codigo = 'PENDIENTE';
    IF v_assignment.estado_id IS NULL THEN RAISE EXCEPTION 'Falta estado PENDIENTE en los datos maestros'; END IF;
    INSERT INTO public.asignaciones SELECT v_assignment.*;
    v_result := public.eliminar_curso_atomico(v_course.id, v_actor);
    ASSERT v_result->>'error_code' = 'COURSE_HAS_FUTURE_ASSIGNMENTS', 'Curso con asignación de hoy';
    v_result := public.eliminar_sala_atomica(v_room.id, v_actor);
    ASSERT v_result->>'error_code' = 'ROOM_HAS_FUTURE_ASSIGNMENTS', 'Sala con asignación de hoy';
    ASSERT NOT EXISTS (SELECT 1 FROM public.audit_logs
        WHERE entity_id IN (v_course.id, v_room.id) AND action IN ('DELETE_COURSE', 'DELETE_ROOM'));

    UPDATE public.asignaciones SET fecha = v_today - 1 WHERE id = v_assignment.id;
    -- Fallar auditoría revierte también la modificación del recurso.
    CREATE TRIGGER test_044_audit BEFORE INSERT ON public.audit_logs
    FOR EACH ROW EXECUTE FUNCTION public.test_044_fail_audit();
    BEGIN
        PERFORM public.eliminar_curso_atomico(v_course.id, v_actor);
        RAISE EXCEPTION 'Se esperaba fallo de auditoría';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'TEST_044_AUDIT_FAILURE' THEN RAISE; END IF;
    END;
    BEGIN
        PERFORM public.eliminar_sala_atomica(v_room.id, v_actor);
        RAISE EXCEPTION 'Se esperaba fallo de auditoría';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'TEST_044_AUDIT_FAILURE' THEN RAISE; END IF;
    END;
    ASSERT (SELECT deleted_at IS NULL AND activo FROM public.cursos_colegio WHERE id = v_course.id);
    ASSERT (SELECT deleted_at IS NULL AND activo FROM public.salas WHERE id = v_room.id);
    DROP TRIGGER test_044_audit ON public.audit_logs;

    v_result := public.eliminar_curso_atomico(v_course.id, v_actor);
    ASSERT v_result->>'ok' = 'true';
    v_result := public.eliminar_sala_atomica(v_room.id, v_actor);
    ASSERT v_result->>'ok' = 'true';
    ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by = v_actor
        FROM public.cursos_colegio WHERE id = v_course.id);
    ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by = v_actor
        FROM public.salas WHERE id = v_room.id);
    ASSERT (SELECT count(*) = 2 FROM public.audit_logs
        WHERE entity_id IN (v_course.id, v_room.id) AND actor_user_id = v_actor
        AND action IN ('DELETE_COURSE', 'DELETE_ROOM')
        AND old_values->>'deleted_at' IS NULL AND new_values->>'deleted_at' IS NOT NULL);
    ASSERT EXISTS (SELECT 1 FROM public.asignaciones WHERE id = v_assignment.id
        AND curso_colegio_id = v_course.id AND sala_id = v_room.id), 'Conservar historial';
    v_result := public.eliminar_curso_atomico(v_course.id, v_actor);
    ASSERT v_result->>'error_code' = 'COURSE_NOT_FOUND';
    v_result := public.eliminar_sala_atomica(v_room.id, v_actor);
    ASSERT v_result->>'error_code' = 'ROOM_NOT_FOUND';

    -- Edición histórica que no reprograma conserva el historial.
    UPDATE public.asignaciones SET observacion = 'Historial conservado' WHERE id = v_assignment.id;
    BEGIN
        UPDATE public.asignaciones SET fecha = v_today + 1 WHERE id = v_assignment.id;
        RAISE EXCEPTION 'Se esperaba bloqueo al reprogramar';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'ASSIGNMENT_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    BEGIN
        v_assignment.id := gen_random_uuid();
        INSERT INTO public.asignaciones SELECT v_assignment.*;
        RAISE EXCEPTION 'Se esperaba bloqueo de nueva asignación';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'ASSIGNMENT_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    -- Aislar el rechazo de sala con un curso que sigue disponible.
    BEGIN
        v_assignment.id := gen_random_uuid();
        v_assignment.curso_colegio_id := v_original_course;
        INSERT INTO public.asignaciones SELECT v_assignment.*;
        RAISE EXCEPTION 'Se esperaba bloqueo de sala eliminada';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'ASSIGNMENT_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    -- Reapertura de una referencia histórica también se bloquea.
    SELECT id INTO v_id FROM public.asignaciones
    WHERE curso_colegio_id = v_course.id AND sala_id = v_room.id LIMIT 1;
    UPDATE public.asignaciones SET activo = false WHERE id = v_id;
    BEGIN
        UPDATE public.asignaciones SET activo = true WHERE id = v_id;
        RAISE EXCEPTION 'Se esperaba bloqueo de reactivación';
    EXCEPTION WHEN check_violation THEN
        IF SQLERRM <> 'ASSIGNMENT_RESOURCE_UNAVAILABLE' THEN RAISE; END IF;
    END;
    RAISE NOTICE '044: pruebas de permisos, conflictos, auditoría, rollback e historial aprobadas';
END;
$$;
ROLLBACK;
