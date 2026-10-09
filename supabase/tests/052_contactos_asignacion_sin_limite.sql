-- Después de 052, fixtures aislados y ROLLBACK. No envía correos.
BEGIN;
DO $$
DECLARE v_school public.colegios%ROWTYPE; v_actor uuid; v_type uuid; v_state uuid;
 v_assignment uuid; v_contact uuid; v_ids uuid[]:=ARRAY[]::uuid[]; v_result jsonb; v_updated timestamptz;
BEGIN
 SELECT u.id INTO v_actor FROM public.usuarios u JOIN public.roles r ON r.id=u.rol_id
 WHERE r.codigo='SUPERADMIN' AND u.activo AND u.deleted_at IS NULL LIMIT 1;
 SELECT * INTO v_school FROM public.colegios WHERE activo AND deleted_at IS NULL LIMIT 1;
 IF v_actor IS NULL OR v_school.id IS NULL THEN RAISE EXCEPTION 'Faltan SUPERADMIN y colegio activos'; END IF;
 v_school.id:=gen_random_uuid(); v_school.rbd:='T052'||left(replace(v_school.id::text,'-',''),16);
 v_school.nombre:='TEST052'; v_school.created_by:=v_actor;
 INSERT INTO public.colegios SELECT v_school.*;
 SELECT id INTO v_type FROM public.tipos_actividad WHERE codigo='REUNION' AND activo;
 SELECT id INTO v_state FROM public.estados_asignacion WHERE codigo='PENDIENTE' AND activo;
 INSERT INTO public.asignaciones(tipo_actividad_id,colegio_id,fecha,hora_inicio,hora_fin,estado_id,created_by)
 VALUES(v_type,v_school.id,current_date+3,'09:00','10:00',v_state,v_actor) RETURNING id INTO v_assignment;
 FOR i IN 1..5 LOOP
  INSERT INTO public.contactos_colegio(colegio_id,nombre,email,telefono,created_by)
  VALUES(v_school.id,'Contacto '||i,'test052-'||i||'@example.org','123456789',v_actor) RETURNING id INTO v_contact;
  v_ids:=array_append(v_ids,v_contact);
  INSERT INTO public.asignacion_contactos(asignacion_id,contacto_colegio_id,created_by)
  VALUES(v_assignment,v_contact,v_actor);
 END LOOP;
 ASSERT (SELECT count(*)=5 FROM public.asignacion_contactos WHERE asignacion_id=v_assignment);
 -- La edición transaccional admite los cinco contactos sin alterar pertenencia.
 SELECT updated_at INTO v_updated FROM public.asignaciones WHERE id=v_assignment;
 v_result:=public.actualizar_asignacion_atomica(v_assignment,'{}',true,
   (SELECT jsonb_agg(jsonb_build_object('contacto_colegio_id',id)) FROM unnest(v_ids) id),v_updated,ARRAY['contactos'],v_actor);
 ASSERT v_result->>'ok'='true';
 ASSERT (SELECT count(*)=5 FROM public.asignacion_contactos WHERE asignacion_id=v_assignment);
 BEGIN
  INSERT INTO public.asignacion_contactos(asignacion_id,contacto_colegio_id,created_by)
  VALUES(v_assignment,v_ids[1],v_actor);
  RAISE EXCEPTION 'Se esperaba bloqueo de duplicado';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 RAISE NOTICE '052: contactos sin máximo, edición y duplicados aprobados';
END;
$$;
ROLLBACK;
