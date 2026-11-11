-- Ejecutar en una base de pruebas aislada después de 056. No llama a Brevo.
-- Requiere roles SUPERADMIN y MONITOR; todos los fixtures se revierten.
BEGIN;
DO $$
DECLARE
 v_admin uuid:=gen_random_uuid(); v_user uuid:=gen_random_uuid();
 v_type uuid; v_pending uuid; v_pending_part uuid; v_accepted uuid; v_rejected uuid;
 v_cancelled uuid; v_observer uuid; v_assignment uuid; v_part uuid; v_notification uuid;
 v_version uuid; v_job jsonb; v_case text; v_offset integer;
 v_priority_pending uuid; v_priority_accepted uuid;
 v_date date:=(now() AT TIME ZONE 'America/Santiago')::date+3;
BEGIN
 INSERT INTO public.usuarios(id,rut,nombres,apellido_paterno,apellido_materno,email,rol_id)
 SELECT v_admin,'TEST056-'||v_admin,'Test','Recordatorios','Admin',v_admin||'@example.org',id
 FROM public.roles WHERE codigo='SUPERADMIN';
 INSERT INTO public.usuarios(id,rut,nombres,apellido_paterno,apellido_materno,email,rol_id)
 SELECT v_user,'TEST056-'||v_user,'Test','Recordatorios','Participante',v_user||'@example.org',id
 FROM public.roles WHERE codigo='MONITOR';
 ASSERT EXISTS(SELECT 1 FROM public.usuarios WHERE id=v_admin), 'Falta rol SUPERADMIN';
 ASSERT EXISTS(SELECT 1 FROM public.usuarios WHERE id=v_user), 'Falta rol MONITOR';
 SELECT id INTO v_type FROM public.tipos_actividad WHERE codigo='CAPACITACION';
 SELECT id INTO v_pending FROM public.estados_asignacion WHERE codigo='PENDIENTE';
 SELECT id INTO v_cancelled FROM public.estados_asignacion WHERE codigo='CANCELADA';
 SELECT id INTO v_pending_part FROM public.estados_participacion WHERE codigo='PENDIENTE';
 SELECT id INTO v_accepted FROM public.estados_participacion WHERE codigo='ACEPTADA';
 SELECT id INTO v_rejected FROM public.estados_participacion WHERE codigo='RECHAZADA';
 SELECT id INTO v_observer FROM public.tipos_participacion WHERE codigo='OBSERVADOR';
 ASSERT NOT has_function_privilege('anon','public.encolar_recordatorios_instancias()','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.encolar_recordatorios_instancias()','EXECUTE');
 ASSERT has_function_privilege('service_role','public.encolar_recordatorios_instancias()','EXECUTE');

 FOREACH v_case IN ARRAY ARRAY['pendiente','aceptada','rechazada','cancelada','eliminada',
                              'retirada','usuario_inactivo','version','fecha','fuera_de_dia'] LOOP
   INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
   VALUES(v_type,'TEST056',v_date,'09:00','10:00',v_pending,v_admin) RETURNING id INTO v_assignment;
   INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
   VALUES(v_assignment,v_user,v_observer,v_pending_part,v_admin) RETURNING id,invitacion_version INTO v_part,v_version;
   IF v_case='aceptada' THEN
     UPDATE public.asignacion_participantes SET estado_participacion_id=v_accepted,fecha_respuesta=now(),respondido_por=v_user WHERE id=v_part;
   END IF;
   PERFORM public.encolar_recordatorios_instancias();
   PERFORM public.encolar_recordatorios_instancias();
   ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part
     AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS'), 'Sin duplicados al repetir la generación';
   ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part
     AND tipo_notificacion='INVITACION_PARTICIPACION'), 'Se conserva invitación independiente';
   SELECT id INTO v_notification FROM public.notificaciones WHERE participacion_id=v_part
     AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS';
   ASSERT (SELECT count(*)=1 FROM public.notificacion_envios WHERE notificacion_id=v_notification);
   -- Aislar la reserva de este caso; no procesa el resto de la cola.
   UPDATE public.notificacion_envios SET proximo_intento=now()+interval '100 days'
   WHERE notificacion_id<>v_notification AND estado='PENDIENTE';

   CASE v_case
   WHEN 'rechazada' THEN UPDATE public.asignacion_participantes SET estado_participacion_id=v_rejected,motivo_rechazo='Test',fecha_respuesta=now(),respondido_por=v_user WHERE id=v_part;
   WHEN 'cancelada' THEN UPDATE public.asignaciones SET estado_id=v_cancelled WHERE id=v_assignment;
   WHEN 'eliminada' THEN UPDATE public.asignaciones SET activo=false,deleted_at=now() WHERE id=v_assignment;
   WHEN 'retirada' THEN UPDATE public.asignacion_participantes SET activo=false,deleted_at=now() WHERE id=v_part;
   WHEN 'usuario_inactivo' THEN UPDATE public.usuarios SET activo=false WHERE id=v_user;
   WHEN 'version' THEN UPDATE public.asignacion_participantes SET invitacion_version=gen_random_uuid() WHERE id=v_part;
   WHEN 'fecha' THEN
     PERFORM set_config('huellapp.edicion_rpc','true',true);
     UPDATE public.asignaciones SET fecha=v_date+1,updated_by=v_admin WHERE id=v_assignment;
   WHEN 'fuera_de_dia' THEN UPDATE public.notificaciones SET recordatorio_fecha=v_date-1 WHERE id=v_notification;
   ELSE NULL;
   END CASE;
   -- Las invitaciones regeneradas por los cambios tampoco se procesan.
   UPDATE public.notificacion_envios SET proximo_intento=now()+interval '100 days'
   WHERE notificacion_id<>v_notification AND estado='PENDIENTE';
   v_job:=public.reservar_envio_participacion();
   IF v_case IN ('pendiente','aceptada') THEN
     ASSERT v_job->'notificacion'->>'id'=v_notification::text, 'Reserva del recordatorio elegible';
     ASSERT public.reservar_envio_participacion() IS NULL, 'No reservar dos veces';
     ASSERT public.finalizar_envio_participacion((v_job->'envio'->>'id')::uuid,
       (v_job->'envio'->>'reserva_id')::uuid,'ENVIADA','TEST056');
     PERFORM public.encolar_recordatorios_instancias();
     ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part
       AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS'), 'No regenerar después del envío';
   ELSE
     ASSERT v_job->>'omitido'='true', 'Suprimir al perder elegibilidad: '||v_case;
     ASSERT (SELECT estado='CANCELADA' FROM public.notificacion_envios WHERE notificacion_id=v_notification);
   END IF;
   IF v_case='version' THEN
     PERFORM public.encolar_recordatorios_instancias();
     ASSERT (SELECT count(*)=2 FROM public.notificaciones WHERE participacion_id=v_part
       AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS'), 'Nueva versión tiene su propio recordatorio';
   ELSIF v_case='fecha' THEN
     PERFORM public.encolar_recordatorios_instancias();
     ASSERT (SELECT count(*)=1 FROM public.notificaciones WHERE participacion_id=v_part
       AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS'), 'Reprogramación espera a tres días antes';
   END IF;
   UPDATE public.usuarios SET activo=true WHERE id=v_user;
 END LOOP;

 -- Ni mañana ni dentro de cuatro días: la ventana no es "menos de tres días".
 FOREACH v_offset IN ARRAY ARRAY[-2,-1,1] LOOP
   INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
   VALUES(v_type,'TEST056 fuera de ventana',v_date+v_offset,'09:00','10:00',v_pending,v_admin) RETURNING id INTO v_assignment;
   INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
   VALUES(v_assignment,v_user,v_observer,v_pending_part,v_admin) RETURNING id INTO v_part;
   PERFORM public.encolar_recordatorios_instancias();
   ASSERT NOT EXISTS(SELECT 1 FROM public.notificaciones WHERE participacion_id=v_part
     AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS');
 END LOOP;

 -- Una confirmación pendiente tiene prioridad frente a una aceptada, aunque se cree después.
 FOREACH v_case IN ARRAY ARRAY['aceptada','pendiente'] LOOP
   INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
   VALUES(v_type,'TEST056 prioridad',v_date,'09:00','10:00',v_pending,v_admin) RETURNING id INTO v_assignment;
   INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
   VALUES(v_assignment,v_user,v_observer,v_pending_part,v_admin) RETURNING id INTO v_part;
   IF v_case='aceptada' THEN
     UPDATE public.asignacion_participantes SET estado_participacion_id=v_accepted,fecha_respuesta=now(),respondido_por=v_user WHERE id=v_part;
   END IF;
   PERFORM public.encolar_recordatorios_instancias();
   SELECT id INTO v_notification FROM public.notificaciones WHERE participacion_id=v_part
     AND tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS';
   IF v_case='aceptada' THEN v_priority_accepted:=v_notification;
   ELSE v_priority_pending:=v_notification; END IF;
 END LOOP;
 UPDATE public.notificacion_envios SET proximo_intento=now()+interval '100 days'
 WHERE notificacion_id NOT IN (v_priority_pending,v_priority_accepted) AND estado='PENDIENTE';
 v_job:=public.reservar_envio_participacion();
 ASSERT v_job->'notificacion'->>'id'=v_priority_pending::text, 'Priorizar pendientes';
 v_job:=public.reservar_envio_participacion();
 ASSERT v_job->'notificacion'->>'id'=v_priority_accepted::text, 'Después recordar a aceptadas';
 RAISE NOTICE '056: duplicados, pendientes, aceptadas, permisos, versiones y supresión aprobados';
END;
$$;
ROLLBACK;
