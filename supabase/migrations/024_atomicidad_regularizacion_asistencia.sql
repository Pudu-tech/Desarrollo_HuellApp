-- ============================================================
-- CORRECCIÓN DEL TRIGGER DE VALIDACIÓN DE ASISTENCIA
-- ============================================================
--
-- La regularización administrativa se identifica mediante
-- motivo_regularizacion, NO comparando si informado_por es
-- distinto al usuario participante.
--
-- Esto permite que una DIRECTIVA regularice incluso su propia
-- asistencia sin exigir GPS.
--
-- La marcación propia continúa requiriendo geolocalización.
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_asistencia_asignacion()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_participante_usuario uuid;
    v_informador_rol varchar;
BEGIN
    -- --------------------------------------------------------
    -- OBTENER USUARIO PARTICIPANTE
    -- --------------------------------------------------------

    SELECT usuario_id
    INTO v_participante_usuario
    FROM public.asignacion_participantes
    WHERE id = NEW.asignacion_participante_id
      AND activo = true
      AND deleted_at IS NULL;

    IF v_participante_usuario IS NULL THEN
        RAISE EXCEPTION
            'El participante no existe o no está activo.';
    END IF;


    -- --------------------------------------------------------
    -- ASISTENCIA PENDIENTE
    -- --------------------------------------------------------
    -- Una asistencia todavía no informada no puede contener
    -- datos propios de marcación o regularización.
    -- --------------------------------------------------------

    IF NEW.estado = 'PENDIENTE' THEN

        IF NEW.informado_por IS NOT NULL
           OR NEW.fecha_informe IS NOT NULL
           OR NEW.latitud IS NOT NULL
           OR NEW.longitud IS NOT NULL
           OR NEW.fecha_geolocalizacion IS NOT NULL
           OR NEW.motivo_regularizacion IS NOT NULL THEN

            RAISE EXCEPTION
                'Una asistencia PENDIENTE no debe contener datos de marcación.';

        END IF;

        RETURN NEW;
    END IF;


    -- --------------------------------------------------------
    -- DATOS OBLIGATORIOS DE UNA ASISTENCIA INFORMADA
    -- --------------------------------------------------------

    IF NEW.informado_por IS NULL
       OR NEW.fecha_informe IS NULL THEN

        RAISE EXCEPTION
            'Una asistencia informada requiere informado_por y fecha_informe.';

    END IF;


    -- --------------------------------------------------------
    -- MOTIVO PARA AUSENTE / JUSTIFICADA
    -- --------------------------------------------------------

    IF NEW.estado IN ('AUSENTE', 'JUSTIFICADA')
       AND (
           NEW.motivo IS NULL
           OR btrim(NEW.motivo) = ''
       ) THEN

        RAISE EXCEPTION
            'AUSENTE y JUSTIFICADA requieren motivo.';

    END IF;


    -- ========================================================
    -- REGULARIZACIÓN ADMINISTRATIVA
    -- ========================================================
    --
    -- La presencia de motivo_regularizacion identifica
    -- explícitamente una regularización administrativa.
    --
    -- Puede realizarse incluso sobre la propia participación
    -- del usuario DIRECTIVA.
    --
    -- No exige GPS.
    -- ========================================================

    IF NEW.motivo_regularizacion IS NOT NULL THEN

        IF btrim(NEW.motivo_regularizacion) = '' THEN
            RAISE EXCEPTION
                'La regularización administrativa requiere motivo_regularizacion.';
        END IF;

        SELECT r.codigo
        INTO v_informador_rol
        FROM public.usuarios u
        JOIN public.roles r
            ON r.id = u.rol_id
        WHERE u.id = NEW.informado_por
          AND u.activo = true
          AND u.deleted_at IS NULL;

        IF v_informador_rol IS NULL THEN
            RAISE EXCEPTION
                'El usuario que regulariza la asistencia no existe o está inactivo.';
        END IF;

        IF v_informador_rol NOT IN (
            'DIRECTIVA',
            'SUPERADMIN'
        ) THEN

            RAISE EXCEPTION
                'Solo DIRECTIVA o SUPERADMIN pueden regularizar asistencia.';

        END IF;

        RETURN NEW;
    END IF;


    -- ========================================================
    -- MARCACIÓN PROPIA
    -- ========================================================
    --
    -- Si no existe motivo_regularizacion, la operación se
    -- considera una marcación realizada por el participante.
    --
    -- Requiere:
    -- - que informado_por sea el propio participante;
    -- - latitud;
    -- - longitud;
    -- - fecha de geolocalización.
    -- ========================================================

    IF NEW.informado_por <> v_participante_usuario THEN

        RAISE EXCEPTION
            'Una asistencia informada por un tercero requiere motivo_regularizacion.';

    END IF;

    IF NEW.latitud IS NULL
       OR NEW.longitud IS NULL
       OR NEW.fecha_geolocalizacion IS NULL THEN

        RAISE EXCEPTION
            'La marcación de asistencia propia requiere geolocalización.';

    END IF;


    RETURN NEW;
END;
$function$;