-- ============================================================
-- HuellAPP
-- Migración 027
-- Registro atómico de asistencia propia
-- ============================================================

BEGIN;


CREATE OR REPLACE FUNCTION public.registrar_asistencia_propia_atomica(
    p_asignacion_id uuid,
    p_participante_id uuid,
    p_estado varchar,
    p_motivo text,
    p_latitud double precision,
    p_longitud double precision,
    p_precision_metros double precision,
    p_fecha_geolocalizacion timestamptz,
    p_actor_user_id uuid,
    p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor record;
    v_asignacion record;
    v_participacion record;
    v_asistencia record;

    v_inicio timestamptz;
    v_limite timestamptz;

    v_old_values jsonb;
    v_new_values jsonb;
BEGIN
    -- --------------------------------------------------------
    -- VALIDACIONES DEL PAYLOAD
    -- --------------------------------------------------------

    IF p_estado NOT IN (
        'PRESENTE',
        'AUSENTE',
        'JUSTIFICADA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_ATTENDANCE_STATE'
        );
    END IF;

    IF p_estado IN ('AUSENTE', 'JUSTIFICADA')
       AND (
           p_motivo IS NULL
           OR length(trim(p_motivo)) = 0
       ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ATTENDANCE_REASON_REQUIRED'
        );
    END IF;

    IF p_latitud IS NULL
       OR p_longitud IS NULL
       OR p_fecha_geolocalizacion IS NULL
       OR p_latitud < -90
       OR p_latitud > 90
       OR p_longitud < -180
       OR p_longitud > 180
       OR (
           p_precision_metros IS NOT NULL
           AND p_precision_metros < 0
       ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'INVALID_GEOLOCATION'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ACTOR Y PERMISO
    -- --------------------------------------------------------

    SELECT
        u.id,
        u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ACTOR_NOT_FOUND'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos p
            ON p.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND p.codigo = 'REPORT_ATTENDANCE'
          AND p.activo = true
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'FORBIDDEN'
        );
    END IF;


    -- --------------------------------------------------------
    -- BLOQUEAR Y VALIDAR ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT
        a.id,
        a.fecha,
        a.hora_inicio,
        a.hora_fin,
        a.estado_id,
        a.activo,
        a.deleted_at,
        ea.codigo AS estado_codigo
    INTO v_asignacion
    FROM public.asignaciones a
    JOIN public.estados_asignacion ea
        ON ea.id = a.estado_id
    WHERE a.id = p_asignacion_id
    FOR UPDATE OF a;

    IF NOT FOUND
       OR v_asignacion.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_NOT_FOUND'
        );
    END IF;

    IF v_asignacion.activo IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_INACTIVE'
        );
    END IF;

    IF v_asignacion.estado_codigo IN (
        'CANCELADA',
        'NO_REALIZADA'
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ASSIGNMENT_CLOSED'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR VENTANA HORARIA
    -- --------------------------------------------------------

    v_inicio :=
        (
            v_asignacion.fecha
            + v_asignacion.hora_inicio
        )
        AT TIME ZONE 'America/Santiago';

    v_limite :=
        (
            (
                v_asignacion.fecha
                + v_asignacion.hora_fin
            )
            AT TIME ZONE 'America/Santiago'
        )
        + interval '24 hours';

    IF CURRENT_TIMESTAMP < v_inicio THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ATTENDANCE_NOT_STARTED'
        );
    END IF;

    IF CURRENT_TIMESTAMP >= v_limite THEN
        -- Actualiza el ciclo de vida si el scheduler aún no lo hizo.
        PERFORM public.evaluar_estado_asignacion(
            p_asignacion_id
        );

        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ATTENDANCE_WINDOW_EXPIRED'
        );
    END IF;


    -- --------------------------------------------------------
    -- VALIDAR PARTICIPACIÓN
    -- --------------------------------------------------------

    SELECT
        ap.id,
        ap.usuario_id,
        ap.estado_participacion_id,
        ep.codigo AS estado_codigo
    INTO v_participacion
    FROM public.asignacion_participantes ap
    JOIN public.estados_participacion ep
        ON ep.id = ap.estado_participacion_id
    WHERE ap.id = p_participante_id
      AND ap.asignacion_id = p_asignacion_id
      AND ap.activo = true
      AND ap.deleted_at IS NULL
    FOR UPDATE OF ap;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_NOT_FOUND'
        );
    END IF;

    IF v_participacion.usuario_id <> p_actor_user_id THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'NOT_PARTICIPANT_OWNER'
        );
    END IF;

    IF v_participacion.estado_codigo <> 'ACEPTADA' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'PARTICIPATION_NOT_ACCEPTED'
        );
    END IF;


    -- --------------------------------------------------------
    -- BLOQUEAR ASISTENCIA
    -- --------------------------------------------------------

    SELECT
        aa.*
    INTO v_asistencia
    FROM public.asistencias_asignacion aa
    WHERE aa.asignacion_participante_id =
        p_participante_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ATTENDANCE_NOT_FOUND'
        );
    END IF;

    IF v_asistencia.estado <> 'PENDIENTE' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ATTENDANCE_ALREADY_REPORTED'
        );
    END IF;


    -- --------------------------------------------------------
    -- AUDITORÍA: VALOR ANTERIOR
    -- --------------------------------------------------------

    v_old_values := jsonb_build_object(
        'id', v_asistencia.id,
        'asignacion_participante_id',
            v_asistencia.asignacion_participante_id,
        'estado', v_asistencia.estado,
        'motivo', v_asistencia.motivo,
        'latitud', v_asistencia.latitud,
        'longitud', v_asistencia.longitud,
        'precision_gps', v_asistencia.precision_metros,
        'fecha_geolocalizacion',
            v_asistencia.fecha_geolocalizacion,
        'direccion_detectada',
            v_asistencia.direccion_detectada,
        'comuna_detectada',
            v_asistencia.comuna_detectada,
        'region_detectada',
            v_asistencia.region_detectada,
        'informado_por',
            v_asistencia.informado_por,
        'fecha_informe',
            v_asistencia.fecha_informe,
        'motivo_regularizacion',
            v_asistencia.motivo_regularizacion,
        'created_at',
            v_asistencia.created_at,
        'updated_at',
            v_asistencia.updated_at
    );


    -- --------------------------------------------------------
    -- REGISTRAR ASISTENCIA
    -- --------------------------------------------------------

    UPDATE public.asistencias_asignacion
    SET
        estado = p_estado,
        motivo = CASE
            WHEN p_estado = 'PRESENTE' THEN NULL
            ELSE trim(p_motivo)
        END,
        latitud = p_latitud,
        longitud = p_longitud,
        precision_metros = p_precision_metros,
        fecha_geolocalizacion =
            p_fecha_geolocalizacion,
        direccion_detectada = NULL,
        comuna_detectada = NULL,
        region_detectada = NULL,
        informado_por = p_actor_user_id,
        fecha_informe = CURRENT_TIMESTAMP,
        motivo_regularizacion = NULL,
        updated_by = p_actor_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_asistencia.id
      AND estado = 'PENDIENTE';

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'error_code', 'ATTENDANCE_CHANGED'
        );
    END IF;


    -- --------------------------------------------------------
    -- AUDITORÍA: VALOR NUEVO
    -- --------------------------------------------------------

    SELECT jsonb_build_object(
        'id', aa.id,
        'asignacion_participante_id',
            aa.asignacion_participante_id,
        'estado', aa.estado,
        'motivo', aa.motivo,
        'latitud', aa.latitud,
        'longitud', aa.longitud,
        'precision_gps', aa.precision_metros,
        'fecha_geolocalizacion',
            aa.fecha_geolocalizacion,
        'direccion_detectada',
            aa.direccion_detectada,
        'comuna_detectada',
            aa.comuna_detectada,
        'region_detectada',
            aa.region_detectada,
        'informado_por',
            aa.informado_por,
        'fecha_informe',
            aa.fecha_informe,
        'motivo_regularizacion',
            aa.motivo_regularizacion,
        'created_at',
            aa.created_at,
        'updated_at',
            aa.updated_at
    )
    INTO v_new_values
    FROM public.asistencias_asignacion aa
    WHERE aa.id = v_asistencia.id;


    -- --------------------------------------------------------
    -- AUDITORÍA
    -- --------------------------------------------------------

    INSERT INTO public.audit_logs (
        actor_user_id,
        actor_role_id,
        action,
        entity_type,
        entity_id,
        old_values,
        new_values,
        description,
        request_id,
        ip_address,
        user_agent,
        source
    )
    VALUES (
        p_actor_user_id,
        v_actor.rol_id,
        'REPORT_ATTENDANCE',
        'ASSIGNMENT_ATTENDANCE',
        v_asistencia.id,
        v_old_values,
        v_new_values,
        'El participante registró su propia asistencia.',
        p_request_id,
        p_ip_address,
        p_user_agent,
        'WEB'
    );


    -- --------------------------------------------------------
    -- EVALUAR CICLO DE VIDA
    -- --------------------------------------------------------
    -- Si la actividad ya terminó y existe al menos un PRESENTE,
    -- evaluar_estado_asignacion puede moverla a REALIZADA.
    -- Todo ocurre dentro de esta misma transacción.
    -- --------------------------------------------------------

    PERFORM public.evaluar_estado_asignacion(
        p_asignacion_id
    );


    RETURN jsonb_build_object(
        'ok', true,
        'asistencia_id', v_asistencia.id
    );
END;
$$;


COMMENT ON FUNCTION public.registrar_asistencia_propia_atomica(
    uuid,
    uuid,
    varchar,
    text,
    double precision,
    double precision,
    double precision,
    timestamptz,
    uuid,
    uuid,
    inet,
    text
) IS
'Registra la asistencia propia con geolocalización, auditoría y evaluación del ciclo de vida en una sola transacción.';


REVOKE ALL ON FUNCTION public.registrar_asistencia_propia_atomica(
    uuid,
    uuid,
    varchar,
    text,
    double precision,
    double precision,
    double precision,
    timestamptz,
    uuid,
    uuid,
    inet,
    text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.registrar_asistencia_propia_atomica(
    uuid,
    uuid,
    varchar,
    text,
    double precision,
    double precision,
    double precision,
    timestamptz,
    uuid,
    uuid,
    inet,
    text
) FROM anon;

REVOKE ALL ON FUNCTION public.registrar_asistencia_propia_atomica(
    uuid,
    uuid,
    varchar,
    text,
    double precision,
    double precision,
    double precision,
    timestamptz,
    uuid,
    uuid,
    inet,
    text
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.registrar_asistencia_propia_atomica(
    uuid,
    uuid,
    varchar,
    text,
    double precision,
    double precision,
    double precision,
    timestamptz,
    uuid,
    uuid,
    inet,
    text
) TO service_role;


COMMIT;