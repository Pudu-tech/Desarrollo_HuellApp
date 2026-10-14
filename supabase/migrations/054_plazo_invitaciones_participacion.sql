-- Alinea los correos con el plazo de respuesta de la migración 053.
BEGIN;
CREATE OR REPLACE FUNCTION public.encolar_invitacion_participacion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_assignment public.asignaciones%ROWTYPE;
BEGIN
 IF TG_OP='UPDATE' AND NEW.invitacion_version=OLD.invitacion_version THEN RETURN NEW; END IF;
 IF NOT NEW.activo OR NEW.deleted_at IS NOT NULL OR NOT EXISTS(
     SELECT 1 FROM public.estados_participacion WHERE id=NEW.estado_participacion_id AND codigo='PENDIENTE') THEN RETURN NEW; END IF;
 SELECT * INTO v_assignment FROM public.asignaciones WHERE id=NEW.asignacion_id;
 IF NOT v_assignment.activo OR v_assignment.deleted_at IS NOT NULL OR NOT EXISTS(
     SELECT 1 FROM public.estados_asignacion WHERE id=v_assignment.estado_id AND codigo IN ('PENDIENTE','CONFIRMADA','REALIZADA')) THEN RETURN NEW; END IF;
 INSERT INTO public.notificaciones(usuario_destino_id,tipo_notificacion,titulo,mensaje,entidad_tipo,entidad_id,
    participacion_id,invitacion_version,expires_at)
 VALUES(NEW.usuario_id,'INVITACION_PARTICIPACION','Nueva asignación en HuellApp',
    'Tienes una participación pendiente de respuesta.','ASSIGNMENT',NEW.asignacion_id,
    NEW.id,NEW.invitacion_version,least(now()+interval '7 days',
      ((v_assignment.fecha+v_assignment.hora_fin) AT TIME ZONE 'America/Santiago') + interval '24 hours')) RETURNING id INTO v_id;
 INSERT INTO public.notificacion_envios(notificacion_id,canal,proveedor)
 VALUES(v_id,'EMAIL','BREVO_ASIGNACIONES');
 RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reservar_envio_participacion() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_envio public.notificacion_envios%ROWTYPE; v_notif public.notificaciones%ROWTYPE;
BEGIN
 UPDATE public.notificacion_intentos i SET estado='INCIERTA',finalizado_at=now(),error_mensaje='Worker interrumpido: verificar entrega en Brevo.'
 FROM public.notificacion_envios e WHERE i.id=e.reserva_id AND i.estado='PROCESANDO'
 AND e.proveedor='BREVO_ASIGNACIONES' AND e.estado='PROCESANDO' AND e.reserva_hasta<now();
 UPDATE public.notificacion_envios SET estado='INCIERTA',error_mensaje='Worker interrumpido: verificar entrega en Brevo.'
 WHERE proveedor='BREVO_ASIGNACIONES' AND estado='PROCESANDO' AND reserva_hasta<now();
 SELECT * INTO v_envio FROM public.notificacion_envios WHERE proveedor='BREVO_ASIGNACIONES'
 AND estado='PENDIENTE' AND proximo_intento<=now() AND intentos<5 ORDER BY proximo_intento,id
 LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO v_notif FROM public.notificaciones WHERE id=v_envio.notificacion_id;
 IF v_notif.expires_at<=now() OR NOT EXISTS(
   SELECT 1 FROM public.asignacion_participantes p JOIN public.asignaciones a ON a.id=p.asignacion_id
   JOIN public.estados_participacion ep ON ep.id=p.estado_participacion_id
   JOIN public.estados_asignacion ea ON ea.id=a.estado_id
   JOIN public.usuarios u ON u.id=p.usuario_id
   WHERE p.id=v_notif.participacion_id AND p.invitacion_version=v_notif.invitacion_version
     AND p.usuario_id=v_notif.usuario_destino_id AND p.activo AND p.deleted_at IS NULL
     AND a.activo AND a.deleted_at IS NULL AND ep.codigo='PENDIENTE'
     AND ea.codigo IN ('PENDIENTE','CONFIRMADA','REALIZADA') AND u.activo AND u.deleted_at IS NULL) THEN
   UPDATE public.notificacion_envios SET estado='CANCELADA',error_mensaje='Invitación vencida, respondida o invalidada.' WHERE id=v_envio.id;
   RETURN jsonb_build_object('omitido',true);
 END IF;
 UPDATE public.notificacion_envios SET estado='PROCESANDO',intentos=intentos+1,fecha_intento=now(),
 reserva_id=gen_random_uuid(),reserva_hasta=now()+interval '5 minutes'
 WHERE id=v_envio.id RETURNING * INTO v_envio;
 INSERT INTO public.notificacion_intentos(id,envio_id,estado) VALUES(v_envio.reserva_id,v_envio.id,'PROCESANDO');
 RETURN jsonb_build_object('envio',to_jsonb(v_envio),'notificacion',to_jsonb(v_notif));
END;
$$;

-- Recupera únicamente versiones actuales, pendientes de respuesta y dentro del plazo.
UPDATE public.notificaciones n
SET expires_at=least(n.created_at+interval '7 days',
 ((a.fecha+a.hora_fin) AT TIME ZONE 'America/Santiago')+interval '24 hours')
FROM public.asignacion_participantes p JOIN public.asignaciones a ON a.id=p.asignacion_id
JOIN public.estados_asignacion ea ON ea.id=a.estado_id
JOIN public.estados_participacion ep ON ep.id=p.estado_participacion_id
JOIN public.usuarios u ON u.id=p.usuario_id
WHERE n.participacion_id=p.id AND n.invitacion_version=p.invitacion_version
AND n.usuario_destino_id=p.usuario_id AND n.tipo_notificacion='INVITACION_PARTICIPACION'
AND p.activo AND p.deleted_at IS NULL AND a.activo AND a.deleted_at IS NULL
AND u.activo AND u.deleted_at IS NULL AND ep.codigo='PENDIENTE'
AND ea.codigo IN ('PENDIENTE','CONFIRMADA','REALIZADA')
AND least(n.created_at+interval '7 days',((a.fecha+a.hora_fin) AT TIME ZONE 'America/Santiago')+interval '24 hours')>now();

-- No reintenta envíos realizados, fallidos o de resultado incierto.
UPDATE public.notificacion_envios e SET estado='PENDIENTE',error_mensaje=NULL,proximo_intento=now()
FROM public.notificaciones n JOIN public.asignacion_participantes p ON p.id=n.participacion_id
JOIN public.asignaciones a ON a.id=p.asignacion_id
JOIN public.estados_asignacion ea ON ea.id=a.estado_id
JOIN public.estados_participacion ep ON ep.id=p.estado_participacion_id
JOIN public.usuarios u ON u.id=p.usuario_id
WHERE e.notificacion_id=n.id AND e.proveedor='BREVO_ASIGNACIONES'
AND e.estado='CANCELADA' AND e.intentos=0
AND e.error_mensaje='Invitación vencida, respondida o invalidada.'
AND n.expires_at>now() AND n.invitacion_version=p.invitacion_version
AND n.usuario_destino_id=p.usuario_id AND p.activo AND p.deleted_at IS NULL
AND a.activo AND a.deleted_at IS NULL AND u.activo AND u.deleted_at IS NULL
AND ep.codigo='PENDIENTE' AND ea.codigo IN ('PENDIENTE','CONFIRMADA','REALIZADA');
COMMIT;