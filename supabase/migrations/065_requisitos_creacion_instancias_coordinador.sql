BEGIN;

CREATE FUNCTION public.validar_creacion_instancia_coordinador()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        JOIN public.roles r ON r.id = u.rol_id
        WHERE u.id = NEW.created_by AND r.codigo = 'COORDINADOR'
    ) THEN
        PERFORM 1
        FROM public.usuario_colegio uc
        JOIN public.colegios c ON c.id = uc.colegio_id
        JOIN public.coordinador_monitor_colegio cmc
          ON cmc.colegio_id = uc.colegio_id AND cmc.coordinador_id = uc.usuario_id
        JOIN public.usuarios m ON m.id = cmc.monitor_id
        JOIN public.roles r ON r.id = m.rol_id
        WHERE uc.usuario_id = NEW.created_by
          AND uc.colegio_id = NEW.colegio_id
          AND uc.activo = true
          AND c.activo = true AND c.deleted_at IS NULL
          AND cmc.activo = true
          AND m.activo = true AND m.deleted_at IS NULL AND r.codigo = 'MONITOR'
        LIMIT 1
        FOR SHARE OF uc, c, cmc, m;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'COORDINATOR_CREATION_SCOPE_REQUIRED';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_creacion_instancia_coordinador
BEFORE INSERT ON public.asignaciones
FOR EACH ROW EXECUTE FUNCTION public.validar_creacion_instancia_coordinador();

COMMIT;
