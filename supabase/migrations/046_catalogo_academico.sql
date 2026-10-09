-- 046: Catálogo transversal auditado. Aplicar después de 045.
-- Conserva todos los IDs y las referencias históricas; no fusiona ramos existentes.
BEGIN;

CREATE TABLE public.ramo_nivel (
    ramo_id uuid NOT NULL REFERENCES public.ramos(id) ON DELETE RESTRICT,
    nivel_curso_id uuid NOT NULL REFERENCES public.niveles_curso(id) ON DELETE RESTRICT,
    PRIMARY KEY (ramo_id, nivel_curso_id)
);
INSERT INTO public.ramo_nivel SELECT id, nivel_curso_id FROM public.ramos;
ALTER TABLE public.ramos ALTER COLUMN nivel_curso_id DROP NOT NULL;
COMMENT ON COLUMN public.ramos.nivel_curso_id IS 'Nivel legado; nuevas consultas usan ramo_nivel. No modificar directamente.';
ALTER TABLE public.ramo_nivel ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ramo_nivel FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.ramo_nivel TO service_role;
CREATE INDEX idx_ramo_nivel_nivel ON public.ramo_nivel(nivel_curso_id);

INSERT INTO public.permisos(codigo, nombre, descripcion, modulo, activo)
SELECT accion || '_ACADEMIC_CATALOG', nombre, 'Catálogo global de asignaturas y espacios académicos.', 'CATALOGO_ACADEMICO', true
FROM (VALUES ('VIEW','Consultar catálogo académico'), ('CREATE','Crear recursos académicos'),
 ('UPDATE','Editar recursos académicos'), ('ACTIVATE','Activar recursos académicos'),
 ('DEACTIVATE','Desactivar recursos académicos'), ('DELETE','Eliminar recursos académicos')) AS x(accion,nombre)
ON CONFLICT(codigo) DO NOTHING;
INSERT INTO public.rol_permiso(rol_id, permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE p.modulo = 'CATALOGO_ACADEMICO'
AND (r.codigo = 'SUPERADMIN' OR (r.codigo IN ('DIRECTIVA','COORDINADOR') AND p.codigo = 'VIEW_ACADEMIC_CATALOG'))
ON CONFLICT(rol_id,permiso_id) DO NOTHING;

-- Unicidad normalizada para nuevas altas/renombres. Los duplicados legados
-- mantienen sus IDs; editar su descripción no obliga a fusionar el historial.
CREATE FUNCTION public.validar_nombre_academico() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_duplicate boolean; v_scope text := ''; v_parent uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.nombre IS NOT DISTINCT FROM OLD.nombre THEN RETURN NEW; END IF;
    NEW.nombre := btrim(NEW.nombre);
    IF NEW.nombre = '' OR length(NEW.nombre) > 150 THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ACADEMIC_INVALID_DATA';
    END IF;
    IF TG_TABLE_NAME <> 'ramos' THEN v_parent := NEW.ramo_id; v_scope := v_parent::text; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(TG_TABLE_NAME || ':' || v_scope || ':' || lower(NEW.nombre), 0));
    IF TG_TABLE_NAME = 'ramos' THEN
        SELECT EXISTS(SELECT 1 FROM public.ramos WHERE id <> NEW.id AND deleted_at IS NULL
            AND lower(btrim(nombre)) = lower(NEW.nombre)) INTO v_duplicate;
    ELSE
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM public.%I WHERE id <> $1 AND ramo_id = $2 AND deleted_at IS NULL AND lower(btrim(nombre)) = lower($3))', TG_TABLE_NAME)
        INTO v_duplicate USING NEW.id, v_parent, NEW.nombre;
    END IF;
    IF v_duplicate THEN RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='ACADEMIC_NAME_EXISTS'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_nombre_academico BEFORE INSERT OR UPDATE OF nombre ON public.ramos
FOR EACH ROW EXECUTE FUNCTION public.validar_nombre_academico();
CREATE TRIGGER trg_nombre_academico BEFORE INSERT OR UPDATE OF nombre ON public.espacios_reflexion
FOR EACH ROW EXECUTE FUNCTION public.validar_nombre_academico();
CREATE TRIGGER trg_nombre_academico BEFORE INSERT OR UPDATE OF nombre ON public.espacios_encuentro
FOR EACH ROW EXECUTE FUNCTION public.validar_nombre_academico();

CREATE FUNCTION public.proteger_espacio_academico() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_parent public.ramos%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.ramo_id IS DISTINCT FROM OLD.ramo_id THEN
            RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ACADEMIC_PARENT_IMMUTABLE';
        END IF;
        IF NOT (NEW.activo AND NOT OLD.activo) AND NOT (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL) THEN RETURN NEW; END IF;
    END IF;
    SELECT * INTO v_parent FROM public.ramos WHERE id=NEW.ramo_id FOR SHARE;
    IF NOT FOUND OR NOT v_parent.activo OR v_parent.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ACADEMIC_PARENT_UNAVAILABLE';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_padre_academico BEFORE INSERT OR UPDATE ON public.espacios_reflexion
FOR EACH ROW EXECUTE FUNCTION public.proteger_espacio_academico();
CREATE TRIGGER trg_padre_academico BEFORE INSERT OR UPDATE ON public.espacios_encuentro
FOR EACH ROW EXECUTE FUNCTION public.proteger_espacio_academico();

-- Se coordina con el bloqueo del RPC: nivel eliminado no puede reservarse
-- concurrentemente. Las ediciones descriptivas del historial siguen permitidas.
CREATE FUNCTION public.proteger_academia_asignacion() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_ramo public.ramos%ROWTYPE; v_nivel uuid; v_ok boolean;
BEGIN
    IF TG_OP='UPDATE' THEN
        IF NEW.ramo_id IS NOT DISTINCT FROM OLD.ramo_id
           AND NEW.espacio_reflexion_id IS NOT DISTINCT FROM OLD.espacio_reflexion_id
           AND NEW.espacio_encuentro_id IS NOT DISTINCT FROM OLD.espacio_encuentro_id
           AND NEW.curso_colegio_id IS NOT DISTINCT FROM OLD.curso_colegio_id
           AND NEW.tipo_actividad_id IS NOT DISTINCT FROM OLD.tipo_actividad_id
           AND NEW.fecha IS NOT DISTINCT FROM OLD.fecha
           AND NOT (NEW.activo AND NOT OLD.activo)
           AND NOT (NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL)
           AND NOT (NEW.estado_id IS DISTINCT FROM OLD.estado_id AND NEW.activo AND NEW.deleted_at IS NULL
             AND NEW.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
             AND EXISTS(SELECT 1 FROM public.estados_asignacion WHERE id=NEW.estado_id
                AND codigo NOT IN ('CANCELADA','REALIZADA','NO_REALIZADA'))) THEN RETURN NEW; END IF;
    END IF;
    IF NEW.ramo_id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO v_ramo FROM public.ramos WHERE id=NEW.ramo_id FOR SHARE;
    IF NOT FOUND OR NOT v_ramo.activo OR v_ramo.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ASSIGNMENT_ACADEMIC_UNAVAILABLE';
    END IF;
    SELECT nivel_curso_id INTO v_nivel FROM public.cursos_colegio WHERE id=NEW.curso_colegio_id FOR SHARE;
    IF NOT EXISTS(SELECT 1 FROM public.ramo_nivel rn JOIN public.niveles_curso n ON n.id=rn.nivel_curso_id
        WHERE rn.ramo_id=NEW.ramo_id AND rn.nivel_curso_id=v_nivel AND n.activo) THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ASSIGNMENT_ACADEMIC_UNAVAILABLE';
    END IF;
    IF NEW.espacio_reflexion_id IS NOT NULL THEN
        SELECT activo AND deleted_at IS NULL AND ramo_id=NEW.ramo_id INTO v_ok
        FROM public.espacios_reflexion WHERE id=NEW.espacio_reflexion_id FOR SHARE;
        IF v_ok IS DISTINCT FROM true THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ASSIGNMENT_ACADEMIC_UNAVAILABLE'; END IF;
    END IF;
    IF NEW.espacio_encuentro_id IS NOT NULL THEN
        SELECT activo AND deleted_at IS NULL AND ramo_id=NEW.ramo_id INTO v_ok
        FROM public.espacios_encuentro WHERE id=NEW.espacio_encuentro_id FOR SHARE;
        IF v_ok IS DISTINCT FROM true THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='ASSIGNMENT_ACADEMIC_UNAVAILABLE'; END IF;
    END IF;
    RETURN NEW;
END;
$$;
-- PostgreSQL ejecuta triggers por nombre. Después de la protección escolar
-- mantiene el orden colegio → curso → sala → asignatura → espacio.
CREATE TRIGGER trg_z_academia_asignacion BEFORE INSERT OR UPDATE ON public.asignaciones
FOR EACH ROW EXECUTE FUNCTION public.proteger_academia_asignacion();

-- La relación también protege escrituras SQL directas, no solo el RPC.
CREATE FUNCTION public.proteger_ramo_nivel() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_ramo uuid; v_nivel uuid;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ACADEMIC_PARENT_IMMUTABLE'; END IF;
 v_ramo := CASE WHEN TG_OP='DELETE' THEN OLD.ramo_id ELSE NEW.ramo_id END;
 v_nivel := CASE WHEN TG_OP='DELETE' THEN OLD.nivel_curso_id ELSE NEW.nivel_curso_id END;
 PERFORM 1 FROM public.ramos WHERE id=v_ramo FOR UPDATE;
 IF TG_OP='DELETE' THEN
   IF EXISTS(SELECT 1 FROM public.asignaciones a JOIN public.cursos_colegio c ON c.id=a.curso_colegio_id
      JOIN public.estados_asignacion e ON e.id=a.estado_id WHERE a.ramo_id=v_ramo AND c.nivel_curso_id=v_nivel
      AND a.activo AND a.deleted_at IS NULL AND a.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
      AND e.codigo NOT IN ('CANCELADA','REALIZADA','NO_REALIZADA')) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ACADEMIC_LEVEL_IN_USE'; END IF;
   RETURN OLD;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ramos WHERE id=v_ramo AND deleted_at IS NULL)
    OR NOT EXISTS(SELECT 1 FROM public.niveles_curso WHERE id=v_nivel AND activo) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ACADEMIC_PARENT_UNAVAILABLE'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER trg_ramo_nivel BEFORE INSERT OR UPDATE OR DELETE ON public.ramo_nivel
FOR EACH ROW EXECUTE FUNCTION public.proteger_ramo_nivel();

-- Cambiar el grado de un curso con referencias académicas reinterpreta también
-- el historial. Se conserva el nivel; para otro grado se crea un curso distinto.
CREATE FUNCTION public.proteger_nivel_curso_academico() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
 IF NEW.nivel_curso_id IS DISTINCT FROM OLD.nivel_curso_id AND EXISTS(
    SELECT 1 FROM public.asignaciones WHERE curso_colegio_id=OLD.id AND ramo_id IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RESOURCE_COURSE_LEVEL_IN_USE'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER trg_nivel_curso_academico BEFORE UPDATE OF nivel_curso_id ON public.cursos_colegio
FOR EACH ROW EXECUTE FUNCTION public.proteger_nivel_curso_academico();

CREATE FUNCTION public.gestionar_catalogo_academico_atomico(
 p_entidad text, p_accion text, p_id uuid, p_datos jsonb, p_actor_user_id uuid,
 p_request_id uuid DEFAULT NULL, p_ip_address inet DEFAULT NULL, p_user_agent text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
 v_actor record; v_table text; v_id uuid := p_id; v_parent uuid;
 v_row jsonb; v_old jsonb; v_new jsonb; v_child record; v_child_new jsonb;
 v_nombre text; v_niveles uuid[]; v_descripcion text; v_orden integer;
BEGIN
 SELECT id,rol_id INTO v_actor FROM public.usuarios WHERE id=p_actor_user_id AND activo AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error_code','ACTOR_NOT_FOUND'); END IF;
 IF p_accion IS NULL OR p_accion NOT IN ('CREATE','UPDATE','ACTIVATE','DEACTIVATE','DELETE')
    OR p_entidad IS NULL OR p_entidad NOT IN ('SUBJECT','REFLECTION_SPACE','ENCOUNTER_SPACE') THEN
    RETURN jsonb_build_object('ok',false,'error_code','INVALID_DATA');
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
   WHERE rp.rol_id=v_actor.rol_id AND p.activo AND p.codigo=p_accion || '_ACADEMIC_CATALOG') THEN
   RETURN jsonb_build_object('ok',false,'error_code','FORBIDDEN');
 END IF;
 v_table := CASE p_entidad WHEN 'SUBJECT' THEN 'ramos' WHEN 'REFLECTION_SPACE' THEN 'espacios_reflexion' ELSE 'espacios_encuentro' END;
 IF p_accion IN ('CREATE','UPDATE') THEN
   IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object' OR EXISTS(
     SELECT 1 FROM jsonb_object_keys(p_datos) AS x(key) WHERE key <> ALL(
       CASE WHEN p_entidad='SUBJECT' THEN ARRAY['nombre','descripcion','nivel_ids'] ELSE ARRAY['nombre','descripcion','orden','ramo_id'] END)) THEN
     RETURN jsonb_build_object('ok',false,'error_code','INVALID_DATA');
   END IF;
   v_nombre := NULLIF(btrim(p_datos->>'nombre'),'');
   v_descripcion := NULLIF(btrim(p_datos->>'descripcion'),'');
   IF v_nombre IS NULL OR length(v_nombre)>150 OR length(v_descripcion)>2000 THEN
      RETURN jsonb_build_object('ok',false,'error_code','INVALID_DATA'); END IF;
   IF p_entidad='SUBJECT' THEN
     IF jsonb_typeof(p_datos->'nivel_ids') IS DISTINCT FROM 'array' THEN RETURN jsonb_build_object('ok',false,'error_code','INVALID_DATA'); END IF;
     SELECT array_agg(DISTINCT value::uuid) INTO v_niveles FROM jsonb_array_elements_text(p_datos->'nivel_ids');
     IF coalesce(cardinality(v_niveles),0)=0 OR EXISTS(SELECT 1 FROM unnest(v_niveles) AS x(id)
       WHERE NOT EXISTS(SELECT 1 FROM public.niveles_curso n WHERE n.id=x.id AND n.activo)) THEN
       RETURN jsonb_build_object('ok',false,'error_code','INVALID_LEVELS'); END IF;
   ELSE
     v_orden := (p_datos->>'orden')::integer;
     IF v_orden < 0 OR v_orden > 9999 THEN RETURN jsonb_build_object('ok',false,'error_code','INVALID_DATA'); END IF;
   END IF;
 END IF;
 -- Orden de bloqueo fijo: asignatura, espacio. No permite traslado de espacios.
 IF p_entidad <> 'SUBJECT' THEN
   IF p_accion='CREATE' THEN v_parent := (p_datos->>'ramo_id')::uuid;
   ELSE
     EXECUTE format('SELECT ramo_id FROM public.%I WHERE id=$1',v_table) INTO v_parent USING p_id;
   END IF;
   PERFORM 1 FROM public.ramos WHERE id=v_parent FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error_code','NOT_FOUND'); END IF;
   IF p_accion IN ('CREATE','UPDATE','ACTIVATE') AND NOT EXISTS(SELECT 1 FROM public.ramos WHERE id=v_parent AND activo AND deleted_at IS NULL) THEN
     RETURN jsonb_build_object('ok',false,'error_code','PARENT_UNAVAILABLE'); END IF;
 END IF;
 IF p_accion <> 'CREATE' THEN
   EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE id=$1 FOR UPDATE',v_table) INTO v_row USING p_id;
   IF v_row IS NULL OR v_row->>'deleted_at' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error_code','NOT_FOUND'); END IF;
   IF p_entidad <> 'SUBJECT' AND p_datos ? 'ramo_id' AND (p_datos->>'ramo_id')::uuid IS DISTINCT FROM v_parent THEN
     RETURN jsonb_build_object('ok',false,'error_code','PARENT_IMMUTABLE'); END IF;
   v_old := v_row;
   IF p_entidad='SUBJECT' THEN
     v_old := v_old || jsonb_build_object('nivel_ids',(SELECT coalesce(jsonb_agg(nivel_curso_id ORDER BY nivel_curso_id),'[]'::jsonb) FROM public.ramo_nivel WHERE ramo_id=p_id));
   END IF;
   IF EXISTS(SELECT 1 FROM public.asignaciones a JOIN public.estados_asignacion e ON e.id=a.estado_id
       LEFT JOIN public.cursos_colegio c ON c.id=a.curso_colegio_id
       WHERE a.activo AND a.deleted_at IS NULL AND a.fecha >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::date
       AND e.codigo NOT IN ('CANCELADA','REALIZADA','NO_REALIZADA')
       AND ((p_entidad='SUBJECT' AND a.ramo_id=p_id AND
             (p_accion IN ('DEACTIVATE','DELETE') OR (p_accion='UPDATE' AND NOT c.nivel_curso_id=ANY(v_niveles))))
         OR (p_entidad='REFLECTION_SPACE' AND a.espacio_reflexion_id=p_id AND p_accion IN ('DEACTIVATE','DELETE'))
         OR (p_entidad='ENCOUNTER_SPACE' AND a.espacio_encuentro_id=p_id AND p_accion IN ('DEACTIVATE','DELETE')))) THEN
     RETURN jsonb_build_object('ok',false,'error_code','HAS_FUTURE_ASSIGNMENTS'); END IF;
 END IF;
 IF p_accion='CREATE' THEN
   v_id := gen_random_uuid();
   IF p_entidad='SUBJECT' THEN
     INSERT INTO public.ramos(id,nombre,descripcion,created_by,updated_by)
     VALUES(v_id,v_nombre,v_descripcion,p_actor_user_id,p_actor_user_id);
   ELSE
     EXECUTE format('INSERT INTO public.%I(id,ramo_id,nombre,descripcion,orden,created_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$6)',v_table)
     USING v_id,v_parent,v_nombre,v_descripcion,v_orden,p_actor_user_id;
   END IF;
 ELSIF p_accion='UPDATE' THEN
   EXECUTE format('UPDATE public.%I SET nombre=$2,descripcion=$3,updated_at=CURRENT_TIMESTAMP,updated_by=$4 WHERE id=$1',v_table)
   USING v_id,v_nombre,v_descripcion,p_actor_user_id;
   IF p_entidad <> 'SUBJECT' THEN
     EXECUTE format('UPDATE public.%I SET orden=$2 WHERE id=$1',v_table) USING v_id,v_orden;
   END IF;
 ELSE
   EXECUTE format('UPDATE public.%I SET activo=$2,deleted_at=CASE WHEN $3 THEN CURRENT_TIMESTAMP ELSE deleted_at END,updated_at=CURRENT_TIMESTAMP,updated_by=$4 WHERE id=$1',v_table)
   USING v_id,p_accion='ACTIVATE',p_accion='DELETE',p_actor_user_id;
 END IF;
 IF p_entidad='SUBJECT' AND p_accion IN ('CREATE','UPDATE') THEN
   -- Nivel legado deja de ser fuente de verdad al administrar el registro.
   UPDATE public.ramos SET nivel_curso_id=NULL WHERE id=v_id;
   DELETE FROM public.ramo_nivel WHERE ramo_id=v_id AND NOT nivel_curso_id=ANY(v_niveles);
   INSERT INTO public.ramo_nivel SELECT v_id,unnest(v_niveles) ON CONFLICT DO NOTHING;
 END IF;
 -- Borrado lógico de los espacios con auditoría individual, en la misma transacción.
 IF p_entidad='SUBJECT' AND p_accion='DELETE' THEN
   FOR v_child IN SELECT 'espacios_reflexion' AS tabla,'REFLECTION_SPACE' AS entidad,id,to_jsonb(s) AS snapshot FROM public.espacios_reflexion s WHERE ramo_id=v_id AND deleted_at IS NULL
     UNION ALL SELECT 'espacios_encuentro','ENCOUNTER_SPACE',id,to_jsonb(s) FROM public.espacios_encuentro s WHERE ramo_id=v_id AND deleted_at IS NULL LOOP
     EXECUTE format('UPDATE public.%I SET activo=false,deleted_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP,updated_by=$2 WHERE id=$1 RETURNING to_jsonb(%I)',v_child.tabla,v_child.tabla)
     INTO v_child_new USING v_child.id,p_actor_user_id;
     INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,description,request_id,ip_address,user_agent,source)
     VALUES(p_actor_user_id,v_actor.rol_id,'DELETE_'||v_child.entidad,v_child.entidad,v_child.id,v_child.snapshot,
       v_child_new || jsonb_build_object('cascade_subject_id',v_id),'Eliminación lógica en cascada de espacio académico.',p_request_id,p_ip_address,p_user_agent,'WEB');
   END LOOP;
 END IF;
 EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE id=$1',v_table) INTO v_new USING v_id;
 IF p_entidad='SUBJECT' THEN v_new := v_new || jsonb_build_object('nivel_ids',
    (SELECT coalesce(jsonb_agg(nivel_curso_id ORDER BY nivel_curso_id),'[]'::jsonb) FROM public.ramo_nivel WHERE ramo_id=v_id)); END IF;
 INSERT INTO public.audit_logs(actor_user_id,actor_role_id,action,entity_type,entity_id,old_values,new_values,description,request_id,ip_address,user_agent,source)
 VALUES(p_actor_user_id,v_actor.rol_id,p_accion||'_'||p_entidad,p_entidad,v_id,v_old,v_new,
   'Operación sobre catálogo académico.',p_request_id,p_ip_address,p_user_agent,'WEB');
 RETURN jsonb_build_object('ok',true,'registro',v_new);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RETURN jsonb_build_object('ok',false,'error_code','INVALID_DATA');
END;
$$;
REVOKE ALL ON FUNCTION public.gestionar_catalogo_academico_atomico(text,text,uuid,jsonb,uuid,uuid,inet,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.gestionar_catalogo_academico_atomico(text,text,uuid,jsonb,uuid,uuid,inet,text) TO service_role;

COMMIT;
