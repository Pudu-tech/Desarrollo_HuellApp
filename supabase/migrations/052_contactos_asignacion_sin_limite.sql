-- Contactos sin límite de cantidad; conserva pertenencia, actividad y disponibilidad.
BEGIN;
CREATE OR REPLACE FUNCTION public.validate_asignacion_contacto()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_assignment record;
    v_school record;
    v_contact record;
    v_type text;
BEGIN
    SELECT * INTO v_assignment FROM public.asignaciones WHERE id = NEW.asignacion_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'La asignación indicada no existe.'; END IF;
    SELECT codigo INTO v_type FROM public.tipos_actividad WHERE id = v_assignment.tipo_actividad_id;
    IF v_type NOT IN ('ESPACIO_REFLEXION', 'ESPACIO_ENCUENTRO', 'REUNION') THEN
        RAISE EXCEPTION 'El tipo de actividad % no admite profesores/contactos.', v_type;
    END IF;
    SELECT activo, deleted_at INTO v_school FROM public.colegios WHERE id = v_assignment.colegio_id FOR SHARE;
    IF NOT FOUND OR NOT v_school.activo OR v_school.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
    END IF;
    SELECT * INTO v_contact FROM public.contactos_colegio WHERE id = NEW.contacto_colegio_id FOR SHARE;
    IF NOT FOUND OR NOT v_contact.activo OR v_contact.deleted_at IS NOT NULL
        OR v_contact.colegio_id IS DISTINCT FROM v_assignment.colegio_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_RESOURCE_UNAVAILABLE';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON TABLE public.asignacion_contactos IS 'Contactos del mismo colegio asociados a una actividad escolar, sin máximo de cantidad.';
COMMIT;
