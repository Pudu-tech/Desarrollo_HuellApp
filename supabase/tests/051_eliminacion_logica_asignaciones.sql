-- DEV/QA después de 051. Fixture aislado; no envía correos.
BEGIN;
CREATE FUNCTION public.test051_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.action='DELETE_ASSIGNMENT' THEN RAISE EXCEPTION 'TEST051_AUDIT_FAILURE'; END IF;
 RETURN NEW;
END;
$$;
DO $$
DECLARE v_actor uuid; v_directiva uuid; v_coord uuid; v_type uuid; v_state uuid;
 v_assignment uuid; v_part uuid; v_part_state uuid; v_part_type uuid; v_result jsonb; v_request uuid:=gen_random_uuid();
BEGIN
 SELECT u.id INTO v_actor FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo='SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 SELECT u.id INTO v_directiva FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo='DIRECTIVA' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 SELECT u.id INTO v_coord FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo='COORDINADOR' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 IF v_actor IS NULL OR v_directiva IS NULL OR v_coord IS NULL THEN RAISE EXCEPTION 'Faltan usuarios activos SUPERADMIN/DIRECTIVA/COORDINADOR'; END IF;
 SELECT id INTO v_type FROM public.tipos_actividad WHERE codigo='CAPACITACION' AND activo;
 SELECT id INTO v_state FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
 ASSERT NOT has_function_privilege('authenticated','public.eliminar_asignacion_atomica(uuid,uuid,uuid,inet,text)','EXECUTE');
 INSERT INTO public.asignaciones(tipo_actividad_id,lugar,fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_type,'TEST051',current_date+3,'09:00','10:00',v_state,v_actor) RETURNING id INTO v_assignment;
 SELECT id INTO v_part_state FROM public.estados_participacion WHERE codigo='PENDIENTE' AND activo;
 SELECT id INTO v_part_type FROM public.tipos_participacion WHERE codigo='RELATOR' AND activo;
 INSERT INTO public.asignacion_participantes(asignacion_id,usuario_id,tipo_participacion_id,estado_participacion_id,created_by)
 VALUES(v_assignment,v_coord,v_part_type,v_part_state,v_actor) RETURNING id INTO v_part;
 -- Incluso una concesión accidental de permiso no habilita COORDINADOR.
 INSERT INTO public.rol_permiso(rol_id,permiso_id)
 SELECT u.rol_id,p.id FROM public.usuarios u CROSS JOIN public.permisos p
 WHERE u.id=v_coord AND p.codigo='DELETE_ASSIGNMENT' ON CONFLICT DO NOTHING;
 v_result:=public.eliminar_asignacion_atomica(v_assignment,v_coord);
 ASSERT v_result->>'error_code'='FORBIDDEN';
 CREATE TRIGGER test051_audit BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.test051_fail_audit();
 BEGIN
  PERFORM public.eliminar_asignacion_atomica(v_assignment,v_actor,v_request);
  RAISE EXCEPTION 'Se esperaba fallo de auditoría';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'TEST051_AUDIT_FAILURE' THEN RAISE; END IF;
 END;
 ASSERT (SELECT activo AND deleted_at IS NULL FROM public.asignaciones WHERE id=v_assignment);
 ASSERT EXISTS(SELECT 1 FROM public.notificacion_envios e JOIN public.notificaciones n ON n.id=e.notificacion_id
  WHERE n.participacion_id=v_part AND e.estado='PENDIENTE');
 ASSERT NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE request_id=v_request);
 DROP TRIGGER test051_audit ON public.audit_logs;
 v_result:=public.eliminar_asignacion_atomica(v_assignment,v_directiva,v_request,'127.0.0.1','test051');
 ASSERT v_result->>'ok'='true';
 ASSERT (SELECT NOT activo AND deleted_at IS NOT NULL AND updated_by=v_directiva FROM public.asignaciones WHERE id=v_assignment);
 ASSERT EXISTS(SELECT 1 FROM public.asignacion_participantes WHERE id=v_part AND estado_participacion_id=v_part_state);
 ASSERT EXISTS(SELECT 1 FROM public.asistencias_asignacion WHERE asignacion_participante_id=v_part AND estado='PENDIENTE');
 ASSERT EXISTS(SELECT 1 FROM public.notificacion_envios e JOIN public.notificaciones n ON n.id=e.notificacion_id
  WHERE n.participacion_id=v_part AND e.estado='CANCELADA' AND n.expires_at<=now());
 ASSERT EXISTS(SELECT 1 FROM public.audit_logs WHERE request_id=v_request AND action='DELETE_ASSIGNMENT'
  AND actor_user_id=v_directiva AND old_values->>'deleted_at' IS NULL AND new_values->>'deleted_at' IS NOT NULL);
 v_result:=public.eliminar_asignacion_atomica(v_assignment,v_actor);
 ASSERT v_result->>'error_code'='NOT_FOUND';
 RAISE NOTICE '051: permisos, eliminación lógica, auditoría y rollback aprobados';
END;
$$;
ROLLBACK;
