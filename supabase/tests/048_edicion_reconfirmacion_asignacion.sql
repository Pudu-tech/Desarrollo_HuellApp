-- DEV/QA después de 048. SUPERADMIN y participante activo con permisos de respuesta.
-- Usa fixtures aislados; no manda correos. Todas las escrituras se revierten.
BEGIN;
CREATE FUNCTION public.test048_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.action='REQUEST_PARTICIPATION_RECONFIRMATION' THEN RAISE EXCEPTION 'TEST048_AUDIT_FAILURE'; END IF;
 RETURN NEW;
END;
$$;
DO $$
DECLARE v_actor uuid; v_user uuid; v_type uuid; v_state uuid; v_pending uuid; v_relator uuid;
 v_assignment uuid; v_part uuid; v_version uuid; v_old_version uuid; v_updated timestamptz; v_old_date date;
 v_result jsonb; v_request uuid:=gen_random_uuid();
BEGIN
 SELECT u.id INTO v_actor FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id WHERE r.codigo='SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 SELECT u.id INTO v_user FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo IN ('MONITOR','COORDINADOR','DIRECTIVA') AND u.activo AND u.deleted_at IS NULL
 AND EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id WHERE rp.rol_id=u.rol_id AND p.codigo='ACCEPT_PARTICIPATION' AND p.activo) LIMIT 1;
 IF v_actor IS NULL OR v_user IS NULL THEN RAISE EXCEPTION 'Faltan SUPERADMIN y participante activos'; END IF;
 SELECT id INTO v_type FROM public.tipos_actividad WHERE codigo='CAPACITACION' AND activo;
 SELECT id INTO v_state FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
 SELECT id INTO v_pending FROM public.estados_participacion WHERE codigo='PENDIENTE' AND activo;
 SELECT id INTO v_relator FROM public.tipos_participacion WHERE codigo='RELATOR' AND activo;
 IF v_type IS NULL OR v_state IS NULL OR v_pending IS NULL OR v_relator IS NULL THEN RAISE EXCEPTION 'Faltan maestros activos'; END IF;
 v_old_date:=(now() AT TIME ZONE 'America/Santiago')::date+3;
 INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_type,'TEST048 lugar',v_old_date,'09:00','10:00',v_state,v_actor) RETURNING id INTO v_assignment;
 INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
 VALUES(v_assignment,v_user,v_relator,v_pending,v_actor) RETURNING id,invitacion_version INTO v_part,v_old_version;
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','WEB');
 ASSERT v_result->>'estado'='ACEPTADA';
 ASSERT (SELECT e.codigo='CONFIRMADA' FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id=a.estado_id WHERE a.id=v_assignment);
 -- Observación: conserva aceptación y versión, no genera otro correo.
 SELECT updated_at INTO v_updated FROM public.asignaciones WHERE id=v_assignment;
 v_result:=public.actualizar_asignacion_atomica(v_assignment,'{"observacion":"Nota de prueba"}',false,'[]',v_updated,ARRAY['observacion'],v_actor);
 ASSERT v_result->>'ok'='true';
 ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part);
 ASSERT (SELECT invitacion_version=v_old_version AND fecha_respuesta IS NOT NULL FROM public.asignacion_participantes WHERE id=v_part);
 -- Una petición sin cambio efectivo tampoco reconfirma.
 SELECT updated_at INTO v_updated FROM public.asignaciones WHERE id=v_assignment;
 v_result:=public.actualizar_asignacion_atomica(v_assignment,jsonb_build_object('fecha',v_old_date),false,'[]',v_updated,ARRAY['fecha'],v_actor);
 ASSERT v_result->>'ok'='true';
 ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part);
 -- Si falla la auditoría, rollback de fecha, respuestas y nueva invitación.
 CREATE TRIGGER test048_audit BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.test048_fail_audit();
 BEGIN
   PERFORM public.actualizar_asignacion_atomica(v_assignment,jsonb_build_object('fecha',v_old_date+1),false,'[]',v_updated,ARRAY['fecha'],v_actor,v_request);
   RAISE EXCEPTION 'Se esperaba fallo de auditoría';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'TEST048_AUDIT_FAILURE' THEN RAISE; END IF;
 END;
 ASSERT (SELECT fecha=v_old_date FROM public.asignaciones WHERE id=v_assignment);
 ASSERT (SELECT invitacion_version=v_old_version AND fecha_respuesta IS NOT NULL FROM public.asignacion_participantes WHERE id=v_part);
 ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part);
 ASSERT NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE request_id=v_request);
 DROP TRIGGER test048_audit ON public.audit_logs;
 SELECT updated_at INTO v_updated FROM public.asignaciones WHERE id=v_assignment;
 v_result:=public.actualizar_asignacion_atomica(v_assignment,jsonb_build_object('fecha',v_old_date+1),false,'[]',v_updated,ARRAY['fecha'],v_actor,v_request,'127.0.0.1','test048');
 ASSERT v_result->>'ok'='true';
 SELECT invitacion_version INTO v_version FROM public.asignacion_participantes WHERE id=v_part;
 ASSERT v_version<>v_old_version;
 ASSERT (SELECT estado_participacion_id=v_pending AND fecha_respuesta IS NULL AND respondido_por IS NULL AND motivo_rechazo IS NULL FROM public.asignacion_participantes WHERE id=v_part);
 ASSERT (SELECT estado_id=v_state FROM public.asignaciones WHERE id=v_assignment);
 ASSERT (SELECT count(*)=2 FROM public.notificaciones WHERE participacion_id=v_part), 'Solo una invitación adicional';
 ASSERT EXISTS(SELECT 1 FROM public.notificaciones WHERE participacion_id=v_part AND invitacion_version=v_version AND titulo='Asignación actualizada en HuellApp');
 ASSERT EXISTS(SELECT 1 FROM public.audit_logs WHERE action='REQUEST_PARTICIPATION_RECONFIRMATION' AND entity_id=v_part AND request_id=v_request
   AND old_values->>'fecha_respuesta' IS NOT NULL AND new_values->>'fecha_respuesta' IS NULL AND ip_address='127.0.0.1');
 ASSERT EXISTS(SELECT 1 FROM public.asistencias_asignacion WHERE asignacion_participante_id=v_part AND estado='PENDIENTE');
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',v_old_version);
 ASSERT v_result->>'error_code'='INVITATION_EXPIRED';
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',v_version);
 ASSERT v_result->>'estado'='ACEPTADA';
 -- Control de concurrencia conservado por la RPC original.
 SELECT updated_at INTO v_updated FROM public.asignaciones WHERE id=v_assignment;
 v_result:=public.actualizar_asignacion_atomica(v_assignment,'{"observacion":"Conflicto"}',false,'[]',v_updated-interval '1 minute',ARRAY['observacion'],v_actor);
 ASSERT v_result->>'error_code'='ASSIGNMENT_CHANGED';
 -- No reinterpretar asistencia ya informada ni fechas históricas.
 BEGIN
   UPDATE public.asignaciones SET fecha=v_old_date-10,updated_by=v_actor WHERE id=v_assignment;
   RAISE EXCEPTION 'Se esperaba bloqueo de reprogramación al pasado';
 EXCEPTION WHEN check_violation THEN IF SQLERRM<>'ASSIGNMENT_RECONFIRMATION_UNAVAILABLE' THEN RAISE; END IF;
 END;
 UPDATE public.asistencias_asignacion SET estado='PRESENTE',informado_por=v_actor,fecha_informe=now(),
   motivo_regularizacion='Fixture transaccional 048' WHERE asignacion_participante_id=v_part;
 BEGIN
   UPDATE public.asignaciones SET hora_fin='11:00',updated_by=v_actor WHERE id=v_assignment;
   RAISE EXCEPTION 'Se esperaba bloqueo por asistencia informada';
 EXCEPTION WHEN check_violation THEN IF SQLERRM<>'ASSIGNMENT_RECONFIRMATION_UNAVAILABLE' THEN RAISE; END IF;
 END;
 RAISE NOTICE '048: edición, invitación única, reconfirmación, auditoría, rollback e historial aprobados';
END;
$$;
ROLLBACK;
