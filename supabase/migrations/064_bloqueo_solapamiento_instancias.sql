-- Valida cruces de horario con los participantes finales de la transacción.
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

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asignacion_participante() IS
'Valida el rol del participante y los datos de su respuesta.';

CREATE OR REPLACE FUNCTION public.validar_horario_participantes()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_asignacion public.asignaciones%ROWTYPE;
    v_asignacion_id uuid;
    v_usuario_id uuid;
    v_participante_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'asignaciones' THEN
        IF NEW.activo IS NOT TRUE OR NEW.deleted_at IS NOT NULL THEN
            RETURN NULL;
        END IF;

        IF (NEW.fecha, NEW.hora_inicio, NEW.hora_fin)
            IS NOT DISTINCT FROM (OLD.fecha, OLD.hora_inicio, OLD.hora_fin)
            AND OLD.activo IS TRUE AND OLD.deleted_at IS NULL
            AND NOT EXISTS (
                SELECT 1 FROM public.estados_asignacion
                WHERE id = OLD.estado_id AND codigo = 'CANCELADA'
            ) THEN
            RETURN NULL;
        END IF;
        v_asignacion_id := NEW.id;
    ELSE
        IF NEW.activo IS NOT TRUE OR NEW.deleted_at IS NOT NULL THEN
            RETURN NULL;
        END IF;

        IF TG_OP = 'UPDATE' THEN
            IF OLD.activo IS TRUE AND OLD.deleted_at IS NULL
                AND (OLD.asignacion_id, OLD.usuario_id) = (NEW.asignacion_id, NEW.usuario_id) THEN
                RETURN NULL;
            END IF;
        END IF;

        v_asignacion_id := NEW.asignacion_id;
        v_participante_id := NEW.id;
    END IF;

    SELECT a.* INTO v_asignacion
    FROM public.asignaciones a
    JOIN public.estados_asignacion e ON e.id = a.estado_id
    WHERE a.id = v_asignacion_id AND a.activo AND a.deleted_at IS NULL
        AND e.codigo <> 'CANCELADA';

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    FOR v_usuario_id IN
        SELECT DISTINCT ap.usuario_id
        FROM public.asignacion_participantes ap
        WHERE ap.asignacion_id = v_asignacion_id AND ap.activo AND ap.deleted_at IS NULL
            AND (v_participante_id IS NULL OR ap.id = v_participante_id)
        ORDER BY ap.usuario_id
    LOOP
        PERFORM pg_advisory_xact_lock(
            hashtextextended(v_usuario_id::text || ':' || v_asignacion.fecha::text, 0)
        );

        IF EXISTS (
            SELECT 1
            FROM public.asignacion_participantes ap
            JOIN public.asignaciones otra ON otra.id = ap.asignacion_id
            JOIN public.estados_asignacion e ON e.id = otra.estado_id
            WHERE ap.usuario_id = v_usuario_id AND ap.activo AND ap.deleted_at IS NULL
                AND otra.id <> v_asignacion_id AND otra.activo AND otra.deleted_at IS NULL
                AND e.codigo <> 'CANCELADA'
                AND otra.fecha = v_asignacion.fecha
                AND otra.hora_inicio < v_asignacion.hora_fin
                AND otra.hora_fin > v_asignacion.hora_inicio
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ASSIGNMENT_SCHEDULE_CONFLICT';
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_horario_participacion
AFTER INSERT OR UPDATE OF asignacion_id, usuario_id, activo, deleted_at
ON public.asignacion_participantes
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.validar_horario_participantes();

CREATE CONSTRAINT TRIGGER trg_horario_asignacion
AFTER UPDATE OF fecha, hora_inicio, hora_fin, estado_id, activo, deleted_at
ON public.asignaciones
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.validar_horario_participantes();

COMMIT;
