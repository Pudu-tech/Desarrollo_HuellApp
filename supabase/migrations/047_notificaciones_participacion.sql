-- 047 · Invitaciones transaccionales, cola Brevo y respuesta única multicanal.
-- Aplicar después de 046. No envía invitaciones antiguas automáticamente.
BEGIN;
ALTER TABLE public.asignacion_participantes ADD COLUMN invitacion_version uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE public.notificaciones
 ADD COLUMN participacion_id uuid REFERENCES public.asignacion_participantes(id) ON DELETE RESTRICT,
 ADD COLUMN invitacion_version uuid,
 ADD COLUMN expires_at timestamptz;
CREATE UNIQUE INDEX uq_notificacion_invitacion ON public.notificaciones(participacion_id,invitacion_version)
WHERE participacion_id IS NOT NULL;
ALTER TABLE public.notificacion_envios
 ADD COLUMN intentos integer NOT NULL DEFAULT 0,
 ADD COLUMN proximo_intento timestamptz NOT NULL DEFAULT now(),
 ADD COLUMN reserva_id uuid,
 ADD COLUMN reserva_hasta timestamptz;
ALTER TABLE public.notificacion_envios DROP CONSTRAINT chk_notificacion_envios_estado;
ALTER TABLE public.notificacion_envios ADD CONSTRAINT chk_notificacion_envios_estado
CHECK(estado IN ('PENDIENTE','ENVIADA','FALLIDA','PROCESANDO','INCIERTA','CANCELADA'));
CREATE UNIQUE INDEX uq_envio_invitacion_email ON public.notificacion_envios(notificacion_id,canal)
WHERE proveedor='BREVO_ASIGNACIONES';
CREATE INDEX idx_envios_pendientes ON public.notificacion_envios(proximo_intento) WHERE estado='PENDIENTE';
CREATE TABLE public.notificacion_intentos (
 id uuid PRIMARY KEY,
 envio_id uuid NOT NULL REFERENCES public.notificacion_envios(id) ON DELETE RESTRICT,
 iniciado_at timestamptz NOT NULL DEFAULT now(),
 finalizado_at timestamptz,
 estado text NOT NULL CHECK(estado IN ('PROCESANDO','ENVIADA','FALLIDA','PENDIENTE','INCIERTA','CANCELADA')),
 identificador_externo text,
 error_mensaje text
);
ALTER TABLE public.notificacion_intentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notificacion_intentos FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.notificacion_intentos TO service_role;
INSERT INTO public.permisos(codigo,nombre,descripcion,modulo,activo) VALUES
 ('VIEW_NOTIFICATION_DELIVERY','Consultar envíos','Estados e intentos de entrega de invitaciones.','NOTIFICACIONES',true),
 ('RETRY_NOTIFICATION_DELIVERY','Reintentar envíos','Reintento explícito después de verificar el proveedor.','NOTIFICACIONES',true)
ON CONFLICT(codigo) DO NOTHING;
INSERT INTO public.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE r.codigo='SUPERADMIN' AND p.codigo IN ('VIEW_NOTIFICATION_DELIVERY','RETRY_NOTIFICATION_DELIVERY')
ON CONFLICT DO NOTHING;

-- Regenerar versión invalida enlaces al reabrir, reasignar o reactivar.
CREATE FUNCTION public.versionar_invitacion_participacion() RETURNS trigger
LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF NEW.usuario_id IS DISTINCT FROM OLD.usuario_id OR NEW.asignacion_id IS DISTINCT FROM OLD.asignacion_id
    OR NEW.tipo_participacion_id IS DISTINCT FROM OLD.tipo_participacion_id
    OR (NEW.activo AND NOT OLD.activo) OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
    OR (NEW.estado_participacion_id IS DISTINCT FROM OLD.estado_participacion_id
       AND EXISTS(SELECT 1 FROM public.estados_participacion WHERE id=NEW.estado_participacion_id AND codigo='PENDIENTE')) THEN
    NEW.invitacion_version:=gen_random_uuid();
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER trg_version_invitacion BEFORE UPDATE ON public.asignacion_participantes
FOR EACH ROW EXECUTE FUNCTION public.versionar_invitacion_participacion();

CREATE FUNCTION public.encolar_invitacion_participacion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_assignment public.asignaciones%ROWTYPE;
BEGIN
 IF TG_OP='UPDATE' AND NEW.invitacion_version=OLD.invitacion_version THEN RETURN NEW; END IF;
 IF NOT NEW.activo OR NEW.deleted_at IS NOT NULL OR NOT EXISTS(
     SELECT 1 FROM public.estados_participacion WHERE id=NEW.estado_participacion_id AND codigo='PENDIENTE') THEN RETURN NEW; END IF;
 SELECT * INTO v_assignment FROM public.asignaciones WHERE id=NEW.asignacion_id;
 IF NOT v_assignment.activo OR v_assignment.deleted_at IS NOT NULL OR NOT EXISTS(
     SELECT 1 FROM public.estados_asignacion WHERE id=v_assignment.estado_id AND codigo IN ('PENDIENTE','CONFIRMADA')) THEN RETURN NEW; END IF;
 INSERT INTO public.notificaciones(usuario_destino_id,tipo_notificacion,titulo,mensaje,entidad_tipo,entidad_id,
    participacion_id,invitacion_version,expires_at)
 VALUES(NEW.usuario_id,'INVITACION_PARTICIPACION','Nueva asignación en HuellApp',
    'Tienes una participación pendiente de respuesta.','ASSIGNMENT',NEW.asignacion_id,
    NEW.id,NEW.invitacion_version,least(now()+interval '7 days',
      (v_assignment.fecha+v_assignment.hora_fin) AT TIME ZONE 'America/Santiago')) RETURNING id INTO v_id;
 INSERT INTO public.notificacion_envios(notificacion_id,canal,proveedor)
 VALUES(v_id,'EMAIL','BREVO_ASIGNACIONES');
 RETURN NEW;
END;
$$;
CREATE TRIGGER trg_encolar_invitacion AFTER INSERT OR UPDATE ON public.asignacion_participantes
FOR EACH ROW EXECUTE FUNCTION public.encolar_invitacion_participacion();

-- Reprogramación/reapertura invalida invitaciones anteriores y renueva pendientes.
CREATE FUNCTION public.renovar_invitaciones_asignacion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NEW.fecha IS DISTINCT FROM OLD.fecha OR NEW.hora_inicio IS DISTINCT FROM OLD.hora_inicio
 OR NEW.hora_fin IS DISTINCT FROM OLD.hora_fin OR NEW.colegio_id IS DISTINCT FROM OLD.colegio_id
 OR NEW.curso_colegio_id IS DISTINCT FROM OLD.curso_colegio_id OR NEW.sala_id IS DISTINCT FROM OLD.sala_id
 OR NEW.ramo_id IS DISTINCT FROM OLD.ramo_id OR NEW.espacio_reflexion_id IS DISTINCT FROM OLD.espacio_reflexion_id
 OR NEW.espacio_encuentro_id IS DISTINCT FROM OLD.espacio_encuentro_id OR NEW.lugar IS DISTINCT FROM OLD.lugar
 OR NEW.tipo_actividad_id IS DISTINCT FROM OLD.tipo_actividad_id OR (NEW.activo AND NOT OLD.activo)
 OR (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
 OR (NEW.estado_id IS DISTINCT FROM OLD.estado_id AND EXISTS(SELECT 1 FROM public.estados_asignacion
    WHERE id=OLD.estado_id AND codigo NOT IN ('PENDIENTE','CONFIRMADA'))) THEN
   UPDATE public.asignacion_participantes SET invitacion_version=gen_random_uuid()
   WHERE asignacion_id=NEW.id AND activo AND deleted_at IS NULL;
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER trg_renovar_invitaciones AFTER UPDATE ON public.asignaciones
FOR EACH ROW EXECUTE FUNCTION public.renovar_invitaciones_asignacion();

-- API/worker: reserva excluyente; una entrega interrumpida queda INCIERTA,
-- no se reenvía a ciegas fuera de la ventana de idempotencia del proveedor.
CREATE FUNCTION public.reservar_envio_participacion() RETURNS jsonb
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
     AND ea.codigo IN ('PENDIENTE','CONFIRMADA') AND u.activo AND u.deleted_at IS NULL) THEN
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
CREATE FUNCTION public.finalizar_envio_participacion(p_id uuid,p_reserva uuid,p_estado text,
 p_externo text DEFAULT NULL,p_error text DEFAULT NULL) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF p_estado NOT IN ('ENVIADA','FALLIDA','PENDIENTE','INCIERTA','CANCELADA') THEN RAISE EXCEPTION 'Estado de entrega inválido'; END IF;
 UPDATE public.notificacion_envios SET
 estado=CASE WHEN p_estado='PENDIENTE' AND intentos>=5 THEN 'FALLIDA' ELSE p_estado END,
 identificador_externo=p_externo,error_mensaje=left(p_error,250),
 fecha_envio=CASE WHEN p_estado='ENVIADA' THEN now() ELSE fecha_envio END,
 proximo_intento=now()+make_interval(secs=>least(900,30*power(2,intentos)::integer)),reserva_hasta=NULL
 WHERE id=p_id AND reserva_id=p_reserva AND estado='PROCESANDO';
 IF NOT FOUND THEN RETURN false; END IF;
 UPDATE public.notificacion_intentos SET estado=p_estado,finalizado_at=now(),identificador_externo=p_externo,error_mensaje=left(p_error,250)
 WHERE id=p_reserva;
 RETURN true;
END;
$$;

CREATE FUNCTION public.reintentar_envio_participacion(p_id uuid,p_actor uuid,p_verificado boolean,
 p_request_id uuid DEFAULT NULL,p_ip_address inet DEFAULT NULL,p_user_agent text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_actor record; v_old public.notificacion_envios%ROWTYPE; v_new public.notificacion_envios%ROWTYPE;
BEGIN
 SELECT rol_id INTO v_actor FROM public.usuarios WHERE id=p_actor AND activo AND deleted_at IS NULL;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
   WHERE rp.rol_id=v_actor.rol_id AND p.codigo='RETRY_NOTIFICATION_DELIVERY' AND p.activo) THEN
   RETURN jsonb_build_object('ok',false,'error_code','FORBIDDEN'); END IF;
 SELECT * INTO v_old FROM public.notificacion_envios WHERE id=p_id AND proveedor='BREVO_ASIGNACIONES' FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error_code','NOT_FOUND'); END IF;
 IF v_old.estado NOT IN ('FALLIDA','INCIERTA') OR (v_old.estado='INCIERTA' AND p_verificado IS DISTINCT FROM true) THEN
   RETURN jsonb_build_object('ok',false,'error_code','DELIVERY_REVIEW_REQUIRED'); END IF;
 UPDATE public.notificacion_envios SET estado='PENDIENTE',intentos=0,proximo_intento=now(),reserva_id=NULL,reserva_hasta=NULL,error_mensaje=NULL
 WHERE id=p_id RETURNING * INTO v_new;
 INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,
    description,request_id,ip_address,user_agent,source)
 VALUES(p_actor,v_actor.rol_id,'RETRY_NOTIFICATION_DELIVERY','NOTIFICATION_DELIVERY',p_id,to_jsonb(v_old),
    to_jsonb(v_new)||jsonb_build_object('entrega_verificada',p_verificado),'Reintento manual de entrega.',p_request_id,p_ip_address,p_user_agent,'WEB');
 RETURN jsonb_build_object('ok',true);
END;
$$;

-- Un solo estado de participación para WEB/EMAIL y el futuro WHATSAPP.
-- Reutiliza RPC existentes, incluidas confirmación del RELATOR y auditoría.
CREATE FUNCTION public.responder_participacion_canal_atomica(
 p_asignacion_id uuid,p_participante_id uuid,p_actor_user_id uuid,p_accion text,p_canal text,
 p_version uuid DEFAULT NULL,p_motivo text DEFAULT NULL,p_request_id uuid DEFAULT NULL,
 p_ip_address inet DEFAULT NULL,p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_a record; v_p record; v_result jsonb; v_rol uuid;
BEGIN
 IF p_accion IS NULL OR p_accion NOT IN ('ACCEPT','REJECT') OR p_canal IS NULL OR p_canal NOT IN ('WEB','EMAIL') THEN
   RETURN jsonb_build_object('ok',false,'error_code','INVALID_RESPONSE'); END IF;
 SELECT a.*,e.codigo AS estado INTO v_a FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id=a.estado_id
 WHERE a.id=p_asignacion_id FOR UPDATE OF a;
 IF NOT FOUND OR NOT v_a.activo OR v_a.deleted_at IS NOT NULL OR v_a.estado NOT IN ('PENDIENTE','CONFIRMADA') THEN
   RETURN jsonb_build_object('ok',false,'error_code','ASSIGNMENT_CLOSED'); END IF;
 SELECT p.*,e.codigo AS estado INTO v_p FROM public.asignacion_participantes p JOIN public.estados_participacion e ON e.id=p.estado_participacion_id
 WHERE p.id=p_participante_id AND p.asignacion_id=p_asignacion_id FOR UPDATE OF p;
 IF NOT FOUND OR NOT v_p.activo OR v_p.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error_code','PARTICIPANT_NOT_FOUND'); END IF;
 IF v_p.usuario_id<>p_actor_user_id OR NOT EXISTS(SELECT 1 FROM public.usuarios WHERE id=p_actor_user_id AND activo AND deleted_at IS NULL) THEN
   RETURN jsonb_build_object('ok',false,'error_code','NOT_PARTICIPANT_OWNER'); END IF;
 IF p_canal='EMAIL' AND (p_version IS NULL OR p_version IS DISTINCT FROM v_p.invitacion_version
    OR NOT EXISTS(SELECT 1 FROM public.notificaciones WHERE participacion_id=v_p.id AND invitacion_version=p_version
       AND usuario_destino_id=p_actor_user_id AND expires_at>now())) THEN
   RETURN jsonb_build_object('ok',false,'error_code','INVITATION_EXPIRED'); END IF;
 IF v_p.estado<>'PENDIENTE' THEN
   RETURN jsonb_build_object('ok',true,'ya_respondida',true,'estado',v_p.estado); END IF;
 IF p_accion='ACCEPT' THEN
   v_result:=public.aceptar_participacion_atomica(p_asignacion_id,p_participante_id,p_actor_user_id,p_request_id,p_ip_address,p_user_agent);
 ELSE
   v_result:=public.rechazar_participacion_atomica(p_asignacion_id,p_participante_id,p_motivo,p_actor_user_id,p_request_id,p_ip_address,p_user_agent);
 END IF;
 IF v_result->>'ok'<>'true' THEN RETURN v_result; END IF;
 SELECT rol_id INTO v_rol FROM public.usuarios WHERE id=p_actor_user_id;
 INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,
   description,request_id,ip_address,user_agent,source)
 VALUES(p_actor_user_id,v_rol,'PARTICIPATION_RESPONSE_CHANNEL','ASSIGNMENT_PARTICIPANT',p_participante_id,
   jsonb_build_object('estado','PENDIENTE'),jsonb_build_object('estado',CASE p_accion WHEN 'ACCEPT' THEN 'ACEPTADA' ELSE 'RECHAZADA' END,'canal',p_canal),
   'Respuesta única a una invitación de participación.',p_request_id,p_ip_address,p_user_agent,p_canal);
 RETURN v_result || jsonb_build_object('estado',CASE p_accion WHEN 'ACCEPT' THEN 'ACEPTADA' ELSE 'RECHAZADA' END,'ya_respondida',false);
END;
$$;

-- Solo el backend puede reservar envíos o actuar como destinatario de un enlace.
REVOKE ALL ON FUNCTION public.reservar_envio_participacion() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.finalizar_envio_participacion(uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.responder_participacion_canal_atomica(uuid,uuid,uuid,text,text,uuid,text,uuid,inet,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.reintentar_envio_participacion(uuid,uuid,boolean,uuid,inet,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.encolar_invitacion_participacion() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.renovar_invitaciones_asignacion() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reservar_envio_participacion() TO service_role;
GRANT EXECUTE ON FUNCTION public.finalizar_envio_participacion(uuid,uuid,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.responder_participacion_canal_atomica(uuid,uuid,uuid,text,text,uuid,text,uuid,inet,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.reintentar_envio_participacion(uuid,uuid,boolean,uuid,inet,text) TO service_role;
COMMIT;
