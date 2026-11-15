-- 057: Evita que un participante tenga dos instancias activas solapadas.
-- Se aplica a cualquier flujo que inserte o reactive una participación, no solo al calendario.
BEGIN;

CREATE OR REPLACE FUNCTION public.validate_asignacion_participante()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_rol varchar;
    v_usuario_activo boolean;
    v_usuario_deleted_at timestamptz;
    v_estado varchar;
    v_asignacion record;
BEGIN
    SELECT r.codigo, u.activo, u.deleted_at
      INTO v_rol, v_usuario_activo, v_usuario_deleted_at
      FROM public.usuarios u
      JOIN public.roles r ON r.id = u.rol_id
     WHERE u.id = NEW.usuario_id;

    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'El usuario participante no existe.';
    END IF;
    IF v_usuario_activo IS NOT TRUE OR v_usuario_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'El usuario participante debe estar activo.';
    END IF;
    IF v_rol NOT IN ('DIRECTIVA', 'COORDINADOR', 'MONITOR') THEN
        RAISE EXCEPTION 'El rol % no puede ser participante de una asignación.', v_rol;
    END IF;

    SELECT codigo INTO v_estado
      FROM public.estados_participacion
     WHERE id = NEW.estado_participacion_id AND activo = true;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de participación no existe o está inactivo.';
    END IF;

    IF v_estado = 'PENDIENTE' THEN
        IF NEW.motivo_rechazo IS NOT NULL OR NEW.fecha_respuesta IS NOT NULL OR NEW.respondido_por IS NOT NULL THEN
            RAISE EXCEPTION 'Una participación PENDIENTE no debe contener datos de respuesta.';
        END IF;
    ELSIF v_estado IN ('ACEPTADA', 'RECHAZADA') AND NEW.respondido_por IS DISTINCT FROM NEW.usuario_id THEN
        RAISE EXCEPTION 'La participación solo puede ser aceptada o rechazada por el propio participante.';
    ELSIF v_estado = 'ACEPTADA' THEN
        IF NEW.fecha_respuesta IS NULL OR NEW.respondido_por IS NULL THEN
            RAISE EXCEPTION 'Una participación ACEPTADA requiere fecha_respuesta y respondido_por.';
        END IF;
        IF NEW.motivo_rechazo IS NOT NULL THEN
            RAISE EXCEPTION 'Una participación ACEPTADA no admite motivo_rechazo.';
        END IF;
    ELSIF v_estado = 'RECHAZADA' THEN
        IF NEW.fecha_respuesta IS NULL OR NEW.respondido_por IS NULL OR NEW.motivo_rechazo IS NULL OR btrim(NEW.motivo_rechazo) = '' THEN
            RAISE EXCEPTION 'Una participación RECHAZADA requiere motivo, fecha_respuesta y respondido_por.';
        END IF;
    END IF;

    -- Solo una participación vigente puede ocupar un bloque horario del usuario.
    IF NEW.activo IS TRUE AND NEW.deleted_at IS NULL THEN
        SELECT a.id, a.fecha, a.hora_inicio, a.hora_fin
          INTO v_asignacion
          FROM public.asignaciones a
         WHERE a.id = NEW.asignacion_id
           AND a.activo IS TRUE
           AND a.deleted_at IS NULL;

        IF v_asignacion.id IS NOT NULL THEN
            -- Serializa validaciones concurrentes del mismo usuario y fecha.
            PERFORM pg_advisory_xact_lock(
                hashtextextended(NEW.usuario_id::text || ':' || v_asignacion.fecha::text, 0)
            );
        END IF;

        IF v_asignacion.id IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.asignacion_participantes ap
              JOIN public.asignaciones otra ON otra.id = ap.asignacion_id
              JOIN public.estados_asignacion ea ON ea.id = otra.estado_id
             WHERE ap.usuario_id = NEW.usuario_id
               AND ap.activo IS TRUE
               AND ap.deleted_at IS NULL
               AND ap.asignacion_id <> NEW.asignacion_id
               AND otra.activo IS TRUE
               AND otra.deleted_at IS NULL
               AND ea.codigo NOT IN ('CANCELADA', 'NO_REALIZADA')
               AND otra.fecha = v_asignacion.fecha
               AND otra.hora_inicio < v_asignacion.hora_fin
               AND otra.hora_fin > v_asignacion.hora_inicio
        ) THEN
            RAISE EXCEPTION 'ASSIGNMENT_SCHEDULE_CONFLICT';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asignacion_participante() IS
'Valida rol/estado del participante e impide participaciones activas con horarios solapados.';

COMMIT;
