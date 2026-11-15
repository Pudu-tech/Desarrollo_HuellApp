-- HuellApp · 059 · Retiro funcional de Salas.
--
-- Conserva tabla/FK y valores históricos de sala_id para trazabilidad,
-- pero las nuevas instancias ya no requieren ni deben usar salas.
BEGIN;

CREATE OR REPLACE FUNCTION public.validate_asignacion_tipo_actividad()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_tipo text;
    v_colegio_curso uuid;
BEGIN
    SELECT codigo INTO v_tipo
      FROM public.tipos_actividad
     WHERE id = NEW.tipo_actividad_id AND activo = true;

    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'El tipo de actividad no existe o está inactivo.';
    END IF;

    IF NEW.curso_colegio_id IS NOT NULL THEN
        SELECT colegio_id INTO v_colegio_curso
          FROM public.cursos_colegio
         WHERE id = NEW.curso_colegio_id;
        IF NEW.colegio_id IS NULL OR v_colegio_curso IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION 'El curso no pertenece al colegio de la asignación.';
        END IF;
    END IF;

    -- Sala queda únicamente como dato histórico. Ninguna creación o cambio de
    -- contexto puede introducir una sala nueva. En una edición histórica sin
    -- modificar sala_id, el valor existente se conserva.
    IF NEW.sala_id IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.sala_id IS DISTINCT FROM OLD.sala_id) THEN
        RAISE EXCEPTION 'Las salas ya no forman parte de las nuevas instancias.';
    END IF;

    IF v_tipo = 'ESPACIO_REFLEXION' THEN
        IF NEW.colegio_id IS NULL OR NEW.curso_colegio_id IS NULL
           OR NEW.ramo_id IS NULL OR NEW.espacio_reflexion_id IS NULL
           OR NEW.espacio_encuentro_id IS NOT NULL OR NEW.lugar IS NOT NULL THEN
            RAISE EXCEPTION 'ESPACIO_REFLEXION requiere colegio, curso, ramo y espacio de reflexión; no admite espacio de encuentro ni lugar.';
        END IF;
    ELSIF v_tipo = 'ESPACIO_ENCUENTRO' THEN
        IF NEW.colegio_id IS NULL OR NEW.curso_colegio_id IS NULL
           OR NEW.ramo_id IS NULL OR NEW.espacio_encuentro_id IS NULL
           OR NEW.espacio_reflexion_id IS NOT NULL OR NEW.lugar IS NOT NULL THEN
            RAISE EXCEPTION 'ESPACIO_ENCUENTRO requiere colegio, curso, ramo y espacio de encuentro; no admite espacio de reflexión ni lugar.';
        END IF;
    ELSIF v_tipo = 'REUNION' THEN
        IF NEW.colegio_id IS NULL OR NEW.ramo_id IS NOT NULL
           OR NEW.espacio_reflexion_id IS NOT NULL OR NEW.espacio_encuentro_id IS NOT NULL
           OR NEW.lugar IS NOT NULL THEN
            RAISE EXCEPTION 'REUNION requiere colegio; curso es opcional; no admite ramo, espacios ni lugar.';
        END IF;
    ELSIF v_tipo IN ('CAPACITACION', 'EVENTO_CASA_CENTRAL') THEN
        IF NEW.colegio_id IS NOT NULL OR NEW.curso_colegio_id IS NOT NULL
           OR NEW.sala_id IS NOT NULL OR NEW.ramo_id IS NOT NULL
           OR NEW.espacio_reflexion_id IS NOT NULL OR NEW.espacio_encuentro_id IS NOT NULL
           OR NEW.lugar IS NULL OR btrim(NEW.lugar) = '' THEN
            RAISE EXCEPTION 'CAPACITACION/EVENTO_CASA_CENTRAL no admite datos escolares y requiere lugar.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Tipo de actividad no soportado: %', v_tipo;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asignacion_tipo_actividad() IS
'Valida instancias sin uso funcional de salas; sala_id se conserva solo para registros históricos.';

COMMIT;
