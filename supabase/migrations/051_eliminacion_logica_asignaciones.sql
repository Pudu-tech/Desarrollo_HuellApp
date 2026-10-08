-- Solo SUPERADMIN y DIRECTIVA pueden retirar asignaciones del uso operativo.
-- Conserva participantes, asistencias, historial y auditorías.
BEGIN;
INSERT INTO public.permisos(codigo,nombre,descripcion,modulo,activo)
VALUES('DELETE_ASSIGNMENT','Eliminar asignaciones','Eliminación lógica auditada de asignaciones.','ASIGNACIONES',true)
ON CONFLICT(codigo) DO UPDATE SET activo=true;
DELETE FROM public.rol_permiso rp USING public.roles r, public.permisos p
WHERE rp.rol_id=r.id AND rp.permiso_id=p.id AND p.codigo='DELETE_ASSIGNMENT'
AND r.codigo NOT IN ('SUPERADMIN','DIRECTIVA');
INSERT INTO public.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE r.codigo IN ('SUPERADMIN','DIRECTIVA') AND p.codigo='DELETE_ASSIGNMENT'
ON CONFLICT(rol_id,permiso_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.eliminar_asignacion_atomica(
 p_asignacion_id uuid,p_actor_user_id uuid,p_request_id uuid DEFAULT NULL,
 p_ip_address inet DEFAULT NULL,p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_actor record; v_old public.asignaciones%ROWTYPE; v_new jsonb;
BEGIN
 SELECT u.rol_id,r.codigo INTO v_actor FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE u.id=p_actor_user_id AND u.activo AND u.deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error_code','ACTOR_NOT_FOUND'); END IF;
 IF v_actor.codigo NOT IN ('SUPERADMIN','DIRECTIVA') OR NOT EXISTS(
  SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
  WHERE rp.rol_id=v_actor.rol_id AND p.codigo='DELETE_ASSIGNMENT' AND p.activo
 ) THEN RETURN jsonb_build_object('ok',false,'error_code','FORBIDDEN'); END IF;
 SELECT * INTO v_old FROM public.asignaciones WHERE id=p_asignacion_id AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error_code','NOT_FOUND'); END IF;
 UPDATE public.asignaciones SET activo=false,deleted_at=now(),updated_by=p_actor_user_id,updated_at=now()
 WHERE id=p_asignacion_id RETURNING to_jsonb(asignaciones) INTO v_new;
 UPDATE public.notificacion_envios e SET estado='CANCELADA',error_mensaje='Asignación eliminada.'
 FROM public.notificaciones n WHERE n.id=e.notificacion_id AND n.entidad_id=p_asignacion_id
 AND e.proveedor='BREVO_ASIGNACIONES' AND e.estado='PENDIENTE';
 UPDATE public.notificaciones SET expires_at=least(expires_at,now())
 WHERE entidad_id=p_asignacion_id AND participacion_id IS NOT NULL;
 INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,
  description,request_id,ip_address,user_agent,source)
 VALUES(p_actor_user_id,v_actor.rol_id,'DELETE_ASSIGNMENT','ASSIGNMENT',p_asignacion_id,to_jsonb(v_old),v_new,
  'Eliminación lógica de asignación.',p_request_id,p_ip_address,p_user_agent,'WEB');
 RETURN jsonb_build_object('ok',true);
END;
$$;
REVOKE ALL ON FUNCTION public.eliminar_asignacion_atomica(uuid,uuid,uuid,inet,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_asignacion_atomica(uuid,uuid,uuid,inet,text) TO service_role;
COMMIT;
