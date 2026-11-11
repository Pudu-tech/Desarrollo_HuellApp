-- Recordatorio por correo tres días calendario antes, en America/Santiago.
-- Una entrega por participación, versión y tipo. Aplicar después de 055.
BEGIN;

DROP INDEX public.uq_notificacion_invitacion;
CREATE UNIQUE INDEX uq_notificacion_invitacion
ON public.notificaciones(participacion_id,invitacion_version,tipo_notificacion)
WHERE participacion_id IS NOT NULL;
ALTER TABLE public.notificaciones ADD COLUMN recordatorio_fecha date;

CREATE FUNCTION public.encolar_recordatorios_instancias() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_count integer;
BEGIN
 WITH nuevas AS (
   INSERT INTO public.notificaciones(usuario_destino_id,tipo_notificacion,titulo,mensaje,
     entidad_tipo,entidad_id,participacion_id,invitacion_version,expires_at,recordatorio_fecha)
   SELECT p.usuario_id,'RECORDATORIO_INSTANCIA_3_DIAS','Recordatorio: tu instancia es en tres días',
     'Revisa los datos de tu instancia. Si aún no has respondido, confirma tu participación.',
     'ASSIGNMENT',a.id,p.id,p.invitacion_version,
     ((a.fecha+a.hora_fin) AT TIME ZONE 'America/Santiago')+interval '24 hours',a.fecha
   FROM public.asignacion_participantes p
   JOIN public.asignaciones a ON a.id=p.asignacion_id
   JOIN public.estados_participacion ep ON ep.id=p.estado_participacion_id
   JOIN public.estados_asignacion ea ON ea.id=a.estado_id
   JOIN public.usuarios u ON u.id=p.usuario_id
   WHERE a.fecha=(now() AT TIME ZONE 'America/Santiago')::date+3
     AND a.activo AND a.deleted_at IS NULL AND ea.codigo IN ('PENDIENTE','CONFIRMADA')
     AND p.activo AND p.deleted_at IS NULL AND ep.codigo IN ('PENDIENTE','ACEPTADA')
     AND u.activo AND u.deleted_at IS NULL AND nullif(trim(u.email),'') IS NOT NULL
   ON CONFLICT (participacion_id,invitacion_version,tipo_notificacion)
     WHERE participacion_id IS NOT NULL DO NOTHING
   RETURNING id
 )
 INSERT INTO public.notificacion_envios(notificacion_id,canal,proveedor)
 SELECT id,'EMAIL','BREVO_ASIGNACIONES' FROM nuevas;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.encolar_recordatorios_instancias() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.encolar_recordatorios_instancias() TO service_role;

-- Se conserva la reserva exclusiva compartida con invitaciones y webhooks.
CREATE OR REPLACE FUNCTION public.reservar_envio_participacion() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_envio public.notificacion_envios%ROWTYPE; v_notif public.notificaciones%ROWTYPE;
BEGIN
 UPDATE public.notificacion_intentos i SET estado='INCIERTA',finalizado_at=now(),error_mensaje='Worker interrumpido: verificar entrega en Brevo.'
 FROM public.notificacion_envios e WHERE i.id=e.reserva_id AND i.estado='PROCESANDO'
 AND e.proveedor='BREVO_ASIGNACIONES' AND e.estado='PROCESANDO' AND e.reserva_hasta<now();
 UPDATE public.notificacion_envios SET estado='INCIERTA',error_mensaje='Worker interrumpido: verificar entrega en Brevo.'
 WHERE proveedor='BREVO_ASIGNACIONES' AND estado='PROCESANDO' AND reserva_hasta<now();
 SELECT e.* INTO v_envio FROM public.notificacion_envios e
 WHERE e.proveedor='BREVO_ASIGNACIONES' AND e.estado='PENDIENTE' AND e.proximo_intento<=now() AND e.intentos<5
 ORDER BY CASE WHEN EXISTS (
   SELECT 1 FROM public.notificaciones n
   JOIN public.asignacion_participantes p ON p.id=n.participacion_id
   JOIN public.estados_participacion ep ON ep.id=p.estado_participacion_id
   WHERE n.id=e.notificacion_id AND ep.codigo='PENDIENTE'
 ) THEN 0 ELSE 1 END,e.proximo_intento,e.id
 LIMIT 1 FOR UPDATE OF e SKIP LOCKED;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO v_notif FROM public.notificaciones WHERE id=v_envio.notificacion_id;
 IF NOT v_notif.activo OR v_notif.expires_at<=now() OR NOT EXISTS(
   SELECT 1 FROM public.asignacion_participantes p JOIN public.asignaciones a ON a.id=p.asignacion_id
   JOIN public.estados_participacion ep ON ep.id=p.estado_participacion_id
   JOIN public.estados_asignacion ea ON ea.id=a.estado_id
   JOIN public.usuarios u ON u.id=p.usuario_id
   WHERE p.id=v_notif.participacion_id AND p.invitacion_version=v_notif.invitacion_version
     AND a.id=v_notif.entidad_id AND p.usuario_id=v_notif.usuario_destino_id
     AND p.activo AND p.deleted_at IS NULL AND a.activo AND a.deleted_at IS NULL
     AND u.activo AND u.deleted_at IS NULL AND nullif(trim(u.email),'') IS NOT NULL
     AND (
       (v_notif.tipo_notificacion='INVITACION_PARTICIPACION' AND ep.codigo='PENDIENTE'
         AND ea.codigo IN ('PENDIENTE','CONFIRMADA','REALIZADA'))
       OR (v_notif.tipo_notificacion='RECORDATORIO_INSTANCIA_3_DIAS'
         AND ep.codigo IN ('PENDIENTE','ACEPTADA') AND ea.codigo IN ('PENDIENTE','CONFIRMADA')
         AND a.fecha=v_notif.recordatorio_fecha
         AND a.fecha=(now() AT TIME ZONE 'America/Santiago')::date+3)
     )) THEN
   UPDATE public.notificacion_envios SET estado='CANCELADA',error_mensaje='Notificación vencida, respondida o invalidada.' WHERE id=v_envio.id;
   RETURN jsonb_build_object('omitido',true);
 END IF;
 UPDATE public.notificacion_envios SET estado='PROCESANDO',intentos=intentos+1,fecha_intento=now(),
 reserva_id=gen_random_uuid(),reserva_hasta=now()+interval '5 minutes'
 WHERE id=v_envio.id RETURNING * INTO v_envio;
 INSERT INTO public.notificacion_intentos(id,envio_id,estado) VALUES(v_envio.reserva_id,v_envio.id,'PROCESANDO');
 RETURN jsonb_build_object('envio',to_jsonb(v_envio),'notificacion',to_jsonb(v_notif));
END;
$$;
COMMIT;
