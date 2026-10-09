-- DEV/QA después de 046. Requiere SUPERADMIN, colegio, dos niveles y ESPACIO_REFLEXION activos.
-- Fixtures aislados; no requiere asignaciones previas. Todo se revierte.
BEGIN;
CREATE FUNCTION public.test_046_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.action='DELETE_REFLECTION_SPACE' THEN RAISE EXCEPTION 'TEST_046_AUDIT_FAILURE'; END IF;
 RETURN NEW;
END;
$$;
DO $$
DECLARE
 v_actor uuid; v_role uuid; v_level1 uuid; v_level2 uuid; v_subject uuid;
 v_reflection uuid; v_encounter uuid; v_course1 uuid; v_course2 uuid; v_room uuid;
 v_activity uuid; v_pending uuid; v_cancelled uuid; v_future uuid; v_past uuid;
 v_result jsonb; v_request uuid := gen_random_uuid();
 v_school public.colegios%ROWTYPE;
 v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date;
 v_name text := 'TEST046 ' || gen_random_uuid()::text;
BEGIN
 -- Los registros legados mantienen su nivel copiado y el RPC no es público.
 ASSERT NOT EXISTS(SELECT 1 FROM public.ramos r WHERE r.nivel_curso_id IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM public.ramo_nivel rn WHERE rn.ramo_id=r.id AND rn.nivel_curso_id=r.nivel_curso_id));
 ASSERT NOT has_function_privilege('authenticated',
   'public.gestionar_catalogo_academico_atomico(text,text,uuid,jsonb,uuid,uuid,inet,text)', 'EXECUTE');
 ASSERT NOT has_function_privilege('anon',
   'public.gestionar_catalogo_academico_atomico(text,text,uuid,jsonb,uuid,uuid,inet,text)', 'EXECUTE');
 SELECT u.id,u.rol_id INTO v_actor,v_role FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo='SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 IF v_actor IS NULL THEN RAISE EXCEPTION 'Falta SUPERADMIN activo'; END IF;
 SELECT id INTO v_level1 FROM public.niveles_curso WHERE activo ORDER BY orden LIMIT 1;
 SELECT id INTO v_level2 FROM public.niveles_curso WHERE activo AND id<>v_level1 ORDER BY orden LIMIT 1;
 IF v_level2 IS NULL THEN RAISE EXCEPTION 'Faltan dos niveles activos'; END IF;
 SELECT * INTO v_school FROM public.colegios WHERE activo AND deleted_at IS NULL ORDER BY id LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Falta colegio activo para copiar ubicación'; END IF;
 SELECT id INTO v_activity FROM public.tipos_actividad WHERE codigo='ESPACIO_REFLEXION' AND activo;
 SELECT id INTO v_pending FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
 SELECT id INTO v_cancelled FROM public.estados_asignacion WHERE codigo='CANCELADA' AND activo;
 IF v_activity IS NULL OR v_pending IS NULL OR v_cancelled IS NULL THEN RAISE EXCEPTION 'Faltan maestros ESPACIO_REFLEXION/PENDIENTE/CANCELADA'; END IF;

 v_school.id:=gen_random_uuid(); v_school.rbd:='T046'||left(replace(v_school.id::text,'-',''),16);
 v_school.nombre:='TEST046 aislado'; v_school.created_by:=v_actor;
 INSERT INTO public.colegios SELECT v_school.*;
 INSERT INTO public.cursos_colegio(colegio_id,nivel_curso_id,seccion,nombre_mostrado,anio,created_by)
 VALUES(v_school.id,v_level1,'A','Curso prueba 1',extract(year FROM v_today)::integer,v_actor) RETURNING id INTO v_course1;
 INSERT INTO public.cursos_colegio(colegio_id,nivel_curso_id,seccion,nombre_mostrado,anio,created_by)
 VALUES(v_school.id,v_level2,'A','Curso prueba 2',extract(year FROM v_today)::integer,v_actor) RETURNING id INTO v_course2;
 INSERT INTO public.salas(colegio_id,nombre,created_by) VALUES(v_school.id,'TEST046 sala',v_actor) RETURNING id INTO v_room;

 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','CREATE',NULL,
   jsonb_build_object('nombre',v_name,'nivel_ids',jsonb_build_array(v_level1,v_level2)),v_actor);
 ASSERT v_result->>'ok'='true', 'Crear asignatura transversal';
 v_subject:=(v_result->'registro'->>'id')::uuid;
 ASSERT (SELECT count(*)=2 FROM public.ramo_nivel WHERE ramo_id=v_subject);
 ASSERT (SELECT nivel_curso_id IS NULL FROM public.ramos WHERE id=v_subject);
 v_result:=public.gestionar_catalogo_academico_atomico('REFLECTION_SPACE','CREATE',NULL,
   jsonb_build_object('nombre','Reflexión prueba','ramo_id',v_subject,'orden',1),v_actor);
 ASSERT v_result->>'ok'='true'; v_reflection:=(v_result->'registro'->>'id')::uuid;
 v_result:=public.gestionar_catalogo_academico_atomico('ENCOUNTER_SPACE','CREATE',NULL,
   jsonb_build_object('nombre','Encuentro prueba','ramo_id',v_subject),v_actor);
 ASSERT v_result->>'ok'='true'; v_encounter:=(v_result->'registro'->>'id')::uuid;
 v_result:=public.gestionar_catalogo_academico_atomico('ENCOUNTER_SPACE','UPDATE',v_encounter,
   jsonb_build_object('nombre','Encuentro prueba','ramo_id',gen_random_uuid()),v_actor);
 ASSERT v_result->>'error_code'='PARENT_IMMUTABLE';

 -- Duplicados normalizados y actor inválido no crean registros.
 BEGIN
  PERFORM public.gestionar_catalogo_academico_atomico('SUBJECT','CREATE',NULL,
    jsonb_build_object('nombre',lower(v_name),'nivel_ids',jsonb_build_array(v_level1)),v_actor);
  RAISE EXCEPTION 'Se esperaba nombre duplicado';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','DELETE',v_subject,'{}',gen_random_uuid());
 ASSERT v_result->>'error_code'='ACTOR_NOT_FOUND';
 DELETE FROM public.rol_permiso WHERE rol_id=v_role AND permiso_id IN
   (SELECT id FROM public.permisos WHERE codigo='DELETE_ACADEMIC_CATALOG');
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','DELETE',v_subject,'{}',v_actor);
 ASSERT v_result->>'error_code'='FORBIDDEN';
 INSERT INTO public.rol_permiso(rol_id,permiso_id) SELECT v_role,id FROM public.permisos WHERE codigo='DELETE_ACADEMIC_CATALOG';

 INSERT INTO public.asignaciones(tipo_actividad_id,colegio_id,curso_colegio_id,sala_id,ramo_id,espacio_reflexion_id,
    fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_activity,v_school.id,v_course1,v_room,v_subject,v_reflection,v_today-1,'09:00','10:00',v_pending,v_actor)
 RETURNING id INTO v_past;
 INSERT INTO public.asignaciones(tipo_actividad_id,colegio_id,curso_colegio_id,sala_id,ramo_id,espacio_reflexion_id,
    fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_activity,v_school.id,v_course2,v_room,v_subject,v_reflection,v_today,'10:00','11:00',v_pending,v_actor)
 RETURNING id INTO v_future;
 -- La misma asignatura admite los dos grados, sin replicarla por colegio.
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','DEACTIVATE',v_subject,'{}',v_actor);
 ASSERT v_result->>'error_code'='HAS_FUTURE_ASSIGNMENTS';
 v_result:=public.gestionar_catalogo_academico_atomico('REFLECTION_SPACE','DELETE',v_reflection,'{}',v_actor);
 ASSERT v_result->>'error_code'='HAS_FUTURE_ASSIGNMENTS';
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','UPDATE',v_subject,
   jsonb_build_object('nombre',v_name,'nivel_ids',jsonb_build_array(v_level1)),v_actor);
 ASSERT v_result->>'error_code'='HAS_FUTURE_ASSIGNMENTS';
 BEGIN
   DELETE FROM public.ramo_nivel WHERE ramo_id=v_subject AND nivel_curso_id=v_level2;
   RAISE EXCEPTION 'Se esperaba bloqueo de nivel por SQL directo';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'ACADEMIC_LEVEL_IN_USE' THEN RAISE; END IF;
 END;
 BEGIN
   UPDATE public.cursos_colegio SET nivel_curso_id=v_level2 WHERE id=v_course1;
   RAISE EXCEPTION 'Se esperaba conservación del grado histórico';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'RESOURCE_COURSE_LEVEL_IN_USE' THEN RAISE; END IF;
 END;
 -- Un nivel solo histórico se retira sin cambiar su asignación anterior.
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','UPDATE',v_subject,
   jsonb_build_object('nombre',v_name,'nivel_ids',jsonb_build_array(v_level2)),v_actor);
 ASSERT v_result->>'ok'='true';
 UPDATE public.asignaciones SET observacion='Historial conservado' WHERE id=v_past;
 BEGIN
   UPDATE public.asignaciones SET fecha=v_today+2 WHERE id=v_past;
   RAISE EXCEPTION 'Se esperaba rechazo por nivel retirado';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'ASSIGNMENT_ACADEMIC_UNAVAILABLE' THEN RAISE; END IF;
 END;
 UPDATE public.asignaciones SET estado_id=v_cancelled WHERE id=v_future;
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','DEACTIVATE',v_subject,'{}',v_actor);
 ASSERT v_result->>'ok'='true';
 v_result:=public.gestionar_catalogo_academico_atomico('REFLECTION_SPACE','CREATE',NULL,
   jsonb_build_object('nombre','Espacio mientras inactiva','ramo_id',v_subject),v_actor);
 ASSERT v_result->>'error_code'='PARENT_UNAVAILABLE';
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','ACTIVATE',v_subject,'{}',v_actor);
 ASSERT v_result->>'ok'='true';

 -- Fallo de un audit_log hijo revierte la cascada completa.
 CREATE TRIGGER test_046_audit BEFORE INSERT ON public.audit_logs
 FOR EACH ROW EXECUTE FUNCTION public.test_046_fail_audit();
 BEGIN
   PERFORM public.gestionar_catalogo_academico_atomico('SUBJECT','DELETE',v_subject,'{}',v_actor,v_request);
   RAISE EXCEPTION 'Se esperaba fallo de auditoría';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'TEST_046_AUDIT_FAILURE' THEN RAISE; END IF;
 END;
 ASSERT (SELECT activo AND deleted_at IS NULL FROM public.ramos WHERE id=v_subject);
 ASSERT (SELECT activo AND deleted_at IS NULL FROM public.espacios_reflexion WHERE id=v_reflection);
 ASSERT (SELECT activo AND deleted_at IS NULL FROM public.espacios_encuentro WHERE id=v_encounter);
 ASSERT NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE request_id=v_request);
 DROP TRIGGER test_046_audit ON public.audit_logs;

 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','DELETE',v_subject,'{}',v_actor,v_request,'127.0.0.1','test046');
 ASSERT v_result->>'ok'='true';
 ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by=v_actor FROM public.ramos WHERE id=v_subject);
 ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL FROM public.espacios_reflexion WHERE id=v_reflection);
 ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL FROM public.espacios_encuentro WHERE id=v_encounter);
 ASSERT (SELECT count(*)=3 FROM public.audit_logs WHERE request_id=v_request AND actor_user_id=v_actor
   AND ip_address='127.0.0.1' AND user_agent='test046' AND old_values->>'deleted_at' IS NULL AND new_values->>'deleted_at' IS NOT NULL);
 ASSERT (SELECT count(*)=2 FROM public.asignaciones WHERE id IN(v_past,v_future));
 UPDATE public.asignaciones SET observacion='Historial después de eliminar' WHERE id=v_past;
 BEGIN
   UPDATE public.asignaciones SET estado_id=v_pending WHERE id=v_future;
   RAISE EXCEPTION 'Se esperaba bloqueo de reapertura';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'ASSIGNMENT_ACADEMIC_UNAVAILABLE' THEN RAISE; END IF;
 END;
 BEGIN
   INSERT INTO public.espacios_reflexion(ramo_id,nombre,created_by) VALUES(v_subject,'Posterior',v_actor);
   RAISE EXCEPTION 'Se esperaba rechazo de nuevo espacio';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'ACADEMIC_PARENT_UNAVAILABLE' THEN RAISE; END IF;
 END;
 v_result:=public.gestionar_catalogo_academico_atomico('SUBJECT','ACTIVATE',v_subject,'{}',v_actor);
 ASSERT v_result->>'error_code'='NOT_FOUND';
 RAISE NOTICE '046: permisos, niveles transversales, conflictos, auditoría, rollback e historial aprobados';
END;
$$;
ROLLBACK;
