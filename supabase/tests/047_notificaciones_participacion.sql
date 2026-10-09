-- DEV/QA después de 047. Requiere SUPERADMIN y participante activo no SUPERADMIN.
-- No envía correos. Cola, auditoría, participaciones y asistencia se revierten.
BEGIN;
CREATE FUNCTION public.test_047_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.action='PARTICIPATION_RESPONSE_CHANNEL' THEN RAISE EXCEPTION 'TEST047_AUDIT_FAILURE'; END IF;
 RETURN NEW;
END;
$$;
DO $$
DECLARE
 v_creator uuid; v_user uuid; v_role uuid; v_type uuid; v_pending uuid; v_pending_part uuid;
 v_relator uuid; v_assignment uuid; v_part uuid; v_part2 uuid; v_notification uuid;
 v_version uuid; v_version2 uuid; v_envio uuid; v_lease uuid;
 v_result jsonb; v_job jsonb; v_request uuid:=gen_random_uuid();
BEGIN
 SELECT u.id INTO v_creator FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo='SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 SELECT u.id,u.rol_id INTO v_user,v_role FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo IN ('DIRECTIVA','COORDINADOR','MONITOR') AND u.activo AND u.deleted_at IS NULL
 AND EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id WHERE rp.rol_id=u.rol_id AND p.codigo='ACCEPT_PARTICIPATION' AND p.activo)
 AND EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id WHERE rp.rol_id=u.rol_id AND p.codigo='REJECT_PARTICIPATION' AND p.activo) LIMIT 1;
 IF v_creator IS NULL OR v_user IS NULL THEN RAISE EXCEPTION 'Faltan SUPERADMIN y participante activos con permisos de respuesta'; END IF;
 SELECT id INTO v_type FROM public.tipos_actividad WHERE codigo='CAPACITACION' AND activo;
 SELECT id INTO v_pending FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
 SELECT id INTO v_pending_part FROM public.estados_participacion WHERE codigo='PENDIENTE' AND activo;
 SELECT id INTO v_relator FROM public.tipos_participacion WHERE codigo='RELATOR' AND activo;
 IF v_type IS NULL OR v_pending IS NULL OR v_pending_part IS NULL OR v_relator IS NULL THEN RAISE EXCEPTION 'Faltan maestros de actividad/participación'; END IF;
 ASSERT NOT has_function_privilege('anon','public.responder_participacion_canal_atomica(uuid,uuid,uuid,text,text,uuid,text,uuid,inet,text)','EXECUTE');
 INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_type,'TEST047',(now() AT TIME ZONE 'America/Santiago')::date+2,'09:00','10:00',v_pending,v_creator) RETURNING id INTO v_assignment;
 INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
 VALUES(v_assignment,v_user,v_relator,v_pending_part,v_creator) RETURNING id,invitacion_version INTO v_part,v_version;
 SELECT id INTO v_notification FROM public.notificaciones WHERE participacion_id=v_part AND invitacion_version=v_version;
 ASSERT v_notification IS NOT NULL;
 ASSERT (SELECT count(*)=1 FROM public.notificacion_envios WHERE notificacion_id=v_notification AND canal='EMAIL' AND estado='PENDIENTE');
 ASSERT NOT EXISTS(SELECT 1 FROM public.notificacion_envios WHERE notificacion_id=v_notification AND canal='WHATSAPP');
 ASSERT EXISTS(SELECT 1 FROM public.asistencias_asignacion WHERE asignacion_participante_id=v_part AND estado='PENDIENTE');
 UPDATE public.asignacion_participantes SET updated_at=now() WHERE id=v_part;
 ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part);
 -- Permisos se validan también en la respuesta por EMAIL.
 DELETE FROM public.rol_permiso WHERE rol_id=v_role AND permiso_id IN (SELECT id FROM public.permisos WHERE codigo='ACCEPT_PARTICIPATION');
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',v_version);
 ASSERT v_result->>'error_code'='FORBIDDEN';
 INSERT INTO public.rol_permiso(rol_id,permiso_id) SELECT v_role,id FROM public.permisos WHERE codigo='ACCEPT_PARTICIPATION';
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_creator,'ACCEPT','EMAIL',v_version);
 ASSERT v_result->>'error_code'='NOT_PARTICIPANT_OWNER';
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',gen_random_uuid());
 ASSERT v_result->>'error_code'='INVITATION_EXPIRED';
 -- Fallo de auditoría revierte aceptación y confirmación automática del relator.
 CREATE TRIGGER test047_audit BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.test_047_fail_audit();
 BEGIN
   PERFORM public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',v_version,NULL,v_request);
   RAISE EXCEPTION 'Se esperaba rollback de auditoría';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'TEST047_AUDIT_FAILURE' THEN RAISE; END IF;
 END;
 ASSERT (SELECT estado_participacion_id=v_pending_part FROM public.asignacion_participantes WHERE id=v_part);
 ASSERT (SELECT estado_id=v_pending FROM public.asignaciones WHERE id=v_assignment);
 ASSERT NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE request_id=v_request);
 DROP TRIGGER test047_audit ON public.audit_logs;
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',v_version,NULL,v_request);
 ASSERT v_result->>'estado'='ACEPTADA' AND v_result->>'ya_respondida'='false';
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'REJECT','WEB',NULL,'Otra respuesta');
 ASSERT v_result->>'estado'='ACEPTADA' AND v_result->>'ya_respondida'='true';
 ASSERT (SELECT count(*)=1 FROM public.audit_logs WHERE entity_id=v_part AND action='PARTICIPATION_RESPONSE_CHANNEL' AND source='EMAIL');
 ASSERT EXISTS(SELECT 1 FROM public.asistencias_asignacion WHERE asignacion_participante_id=v_part AND estado='PENDIENTE');
 -- Reabrir genera nueva versión; el correo anterior no puede responderla.
 UPDATE public.asignacion_participantes SET estado_participacion_id=v_pending_part,motivo_rechazo=NULL,fecha_respuesta=NULL,respondido_por=NULL WHERE id=v_part
 RETURNING invitacion_version INTO v_version2;
 ASSERT v_version2<>v_version;
 ASSERT (SELECT count(*)=2 FROM public.notificaciones WHERE participacion_id=v_part);
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'ACCEPT','EMAIL',v_version);
 ASSERT v_result->>'error_code'='INVITATION_EXPIRED';
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part,v_user,'REJECT','EMAIL',v_version2,'No disponible');
 ASSERT v_result->>'estado'='RECHAZADA';

 -- Otra asignación para verificar reserva, intento, fallo y reintento del worker.
 INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_type,'TEST047 cola',(now() AT TIME ZONE 'America/Santiago')::date+3,'09:00','10:00',v_pending,v_creator) RETURNING id INTO v_assignment;
 INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
 VALUES(v_assignment,v_user,v_relator,v_pending_part,v_creator) RETURNING id,invitacion_version INTO v_part2,v_version;
 SELECT id INTO v_notification FROM public.notificaciones WHERE participacion_id=v_part2;
 -- Aislar el test sin procesar cola real. Estos cambios también se revierten.
 UPDATE public.notificacion_envios SET proximo_intento=now()+interval '100 days'
 WHERE proveedor='BREVO_ASIGNACIONES' AND notificacion_id<>v_notification AND estado='PENDIENTE';
 v_job:=public.reservar_envio_participacion();
 v_envio:=(v_job->'envio'->>'id')::uuid; v_lease:=(v_job->'envio'->>'reserva_id')::uuid;
 ASSERT v_job->'envio'->>'estado'='PROCESANDO';
 ASSERT public.reservar_envio_participacion() IS NULL, 'No reservar dos veces';
 ASSERT NOT public.finalizar_envio_participacion(v_envio,gen_random_uuid(),'ENVIADA'), 'No aceptar reserva ajena';
 ASSERT public.finalizar_envio_participacion(v_envio,v_lease,'INCIERTA',NULL,'TEST timeout');
 ASSERT EXISTS(SELECT 1 FROM public.notificacion_intentos WHERE id=v_lease AND estado='INCIERTA' AND finalizado_at IS NOT NULL);
 v_result:=public.reintentar_envio_participacion(v_envio,v_creator,false);
 ASSERT v_result->>'error_code'='DELIVERY_REVIEW_REQUIRED';
 v_result:=public.reintentar_envio_participacion(v_envio,v_creator,true);
 ASSERT v_result->>'ok'='true';
 v_job:=public.reservar_envio_participacion(); v_lease:=(v_job->'envio'->>'reserva_id')::uuid;
 ASSERT public.finalizar_envio_participacion(v_envio,v_lease,'ENVIADA','TEST brevo message');
 ASSERT (SELECT count(*)=2 FROM public.notificacion_intentos WHERE envio_id=v_envio);
 v_result:=public.reintentar_envio_participacion(v_envio,v_creator,true);
 ASSERT v_result->>'error_code'='DELIVERY_REVIEW_REQUIRED', 'No reenviar entrega confirmada';
 -- Invitación vencida, sin necesidad de esperar el reloj.
 UPDATE public.notificaciones SET expires_at=now()-interval '1 minute' WHERE id=v_notification;
 v_result:=public.responder_participacion_canal_atomica(v_assignment,v_part2,v_user,'ACCEPT','EMAIL',v_version);
 ASSERT v_result->>'error_code'='INVITATION_EXPIRED';
 RAISE NOTICE '047: cola, permisos, respuesta única, versiones, rollback, asistencia separada y reservas aprobados';
END;
$$;
ROLLBACK;
