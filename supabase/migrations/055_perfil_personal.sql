-- Perfil propio para todos los roles; foto privada y cambios auditados.
BEGIN;
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS foto_perfil_path text;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('profile-photos','profile-photos',false,3145728,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT(id) DO NOTHING;
CREATE OR REPLACE FUNCTION public.actualizar_perfil_propio(p_actor uuid,p_telefono text,p_foto text,p_cambiar_foto boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old public.usuarios%ROWTYPE; v_new public.usuarios%ROWTYPE;
BEGIN
 SELECT * INTO v_old FROM public.usuarios WHERE id=p_actor AND activo AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
 IF p_cambiar_foto AND p_foto IS NOT NULL AND p_foto NOT LIKE p_actor::text||'/%' THEN RAISE EXCEPTION 'INVALID_PHOTO_PATH'; END IF;
 UPDATE public.usuarios SET telefono=nullif(trim(p_telefono),''),
 foto_perfil_path=CASE WHEN p_cambiar_foto THEN p_foto ELSE foto_perfil_path END,
 updated_at=now(),updated_by=p_actor WHERE id=p_actor RETURNING * INTO v_new;
 INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,description,source)
 VALUES(p_actor,v_old.rol_id,'UPDATE_OWN_PROFILE','USER',p_actor,
 jsonb_build_object('telefono',v_old.telefono,'foto_perfil_path',v_old.foto_perfil_path),
 jsonb_build_object('telefono',v_new.telefono,'foto_perfil_path',v_new.foto_perfil_path),'Actualización del perfil personal.','WEB');
 RETURN to_jsonb(v_new);
END;
$$;
REVOKE ALL ON FUNCTION public.actualizar_perfil_propio(uuid,text,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_perfil_propio(uuid,text,text,boolean) TO service_role;
COMMIT;
