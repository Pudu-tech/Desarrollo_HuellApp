-- ============================================================
-- HuellAPP
-- Migración 014
-- Ciclo de vida automático de asignaciones
-- ============================================================
--
-- REGLAS:
--
-- 1. Una asignación NO puede pasar a REALIZADA antes de terminar.
--
-- 2. Una vez terminado su horario:
--
--      existe al menos una asistencia PRESENTE
--          -> REALIZADA
--
-- 3. Si transcurren 24 horas desde hora_fin y continúa sin existir
--    ninguna asistencia PRESENTE:
--
--          -> NO_REALIZADA
--
-- 4. CANCELADA nunca participa en este flujo automático.
--
-- 5. REALIZADA no vuelve automáticamente hacia atrás.
--
-- 6. NO_REALIZADA tampoco vuelve automáticamente a otro estado.
--    Su regularización posterior será administrada exclusivamente
--    por DIRECTIVA o SUPERADMIN desde backend.
--
-- 7. Se consideran todas las participaciones vinculadas a la
--    asignación, incluyendo participaciones archivadas, porque
--    su asistencia forma parte de la historia real de la actividad.
--
-- IMPORTANTE:
-- La fecha y hora de las actividades se interpretan en horario
-- de Chile mediante America/Santiago para manejar correctamente
-- cambios de horario de verano/invierno.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. EVALUAR UNA ASIGNACIÓN
-- ============================================================

CREATE OR REPLACE FUNCTION public.evaluar_estado_asignacion(
    p_asignacion_id uuid
)
RETURNS varchar
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_asignacion record;

    v_estado_actual varchar;

    v_estado_realizada_id uuid;
    v_estado_no_realizada_id uuid;

    v_fin_actividad timestamptz;

    v_tiene_presente boolean := false;
BEGIN

    -- --------------------------------------------------------
    -- OBTENER ASIGNACIÓN Y ESTADO ACTUAL
    -- --------------------------------------------------------

    SELECT
        a.id,
        a.fecha,
        a.hora_fin,
        a.estado_id,
        a.activo,
        a.deleted_at,
        ea.codigo AS estado_codigo
    INTO v_asignacion
    FROM public.asignaciones a
    JOIN public.estados_asignacion ea
        ON ea.id = a.estado_id
    WHERE a.id = p_asignacion_id;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'La asignación % no existe.',
            p_asignacion_id;
    END IF;


    IF v_asignacion.deleted_at IS NOT NULL THEN
        RETURN v_asignacion.estado_codigo;
    END IF;


    IF v_asignacion.activo IS NOT TRUE THEN
        RETURN v_asignacion.estado_codigo;
    END IF;


    v_estado_actual := v_asignacion.estado_codigo;


    -- --------------------------------------------------------
    -- ESTADOS QUE NO DEBEN SER MODIFICADOS AUTOMÁTICAMENTE
    -- --------------------------------------------------------

    IF v_estado_actual IN (
        'CANCELADA',
        'REALIZADA',
        'NO_REALIZADA'
    ) THEN
        RETURN v_estado_actual;
    END IF;


    -- --------------------------------------------------------
    -- MOMENTO REAL DE TÉRMINO
    -- --------------------------------------------------------
    --
    -- fecha + hora_fin genera timestamp sin timezone.
    -- AT TIME ZONE America/Santiago lo convierte al instante real
    -- correspondiente, respetando horario de verano/invierno.
    -- --------------------------------------------------------

    v_fin_actividad :=
        (
            v_asignacion.fecha
            + v_asignacion.hora_fin
        )
        AT TIME ZONE 'America/Santiago';


    -- --------------------------------------------------------
    -- SI TODAVÍA NO TERMINA, NO CAMBIAR ESTADO
    -- --------------------------------------------------------

    IF CURRENT_TIMESTAMP <= v_fin_actividad THEN
        RETURN v_estado_actual;
    END IF;


    -- --------------------------------------------------------
    -- VERIFICAR SI EXISTE AL MENOS UNA ASISTENCIA PRESENTE
    -- --------------------------------------------------------
    --
    -- No filtramos por activo/deleted_at en participantes porque
    -- las participaciones históricas mantienen su asistencia.
    -- --------------------------------------------------------

    SELECT EXISTS (
        SELECT 1
        FROM public.asignacion_participantes ap
        JOIN public.asistencias_asignacion aa
            ON aa.asignacion_participante_id = ap.id
        WHERE ap.asignacion_id = p_asignacion_id
          AND aa.estado = 'PRESENTE'
    )
    INTO v_tiene_presente;


    -- --------------------------------------------------------
    -- TERMINÓ + EXISTE PRESENTE = REALIZADA
    -- --------------------------------------------------------

    IF v_tiene_presente THEN

        SELECT id
        INTO v_estado_realizada_id
        FROM public.estados_asignacion
        WHERE codigo = 'REALIZADA'
          AND activo = true
        LIMIT 1;


        IF v_estado_realizada_id IS NULL THEN
            RAISE EXCEPTION
                'No existe el estado REALIZADA activo.';
        END IF;


        UPDATE public.asignaciones
        SET
            estado_id = v_estado_realizada_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_asignacion_id
          AND estado_id = v_asignacion.estado_id;


        RETURN 'REALIZADA';

    END IF;


    -- --------------------------------------------------------
    -- +24 HORAS SIN PRESENTES = NO_REALIZADA
    -- --------------------------------------------------------

    IF CURRENT_TIMESTAMP >= (
        v_fin_actividad + interval '24 hours'
    ) THEN

        SELECT id
        INTO v_estado_no_realizada_id
        FROM public.estados_asignacion
        WHERE codigo = 'NO_REALIZADA'
          AND activo = true
        LIMIT 1;


        IF v_estado_no_realizada_id IS NULL THEN
            RAISE EXCEPTION
                'No existe el estado NO_REALIZADA activo.';
        END IF;


        UPDATE public.asignaciones
        SET
            estado_id = v_estado_no_realizada_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_asignacion_id
          AND estado_id = v_asignacion.estado_id;


        RETURN 'NO_REALIZADA';

    END IF;


    -- --------------------------------------------------------
    -- TERMINÓ, PERO SIGUE DENTRO DE LA VENTANA DE 24 HORAS
    -- --------------------------------------------------------

    RETURN v_estado_actual;

END;
$$;


COMMENT ON FUNCTION public.evaluar_estado_asignacion(uuid) IS
'Evalúa automáticamente el ciclo de vida de una asignación: terminada con al menos una asistencia PRESENTE pasa a REALIZADA; luego de 24 horas sin PRESENTE pasa a NO_REALIZADA. CANCELADA, REALIZADA y NO_REALIZADA no se modifican automáticamente.';


-- ============================================================
-- 2. EVALUAR TODAS LAS ASIGNACIONES PENDIENTES DE CIERRE
-- ============================================================
--
-- Esta función podrá ser utilizada posteriormente por:
--
-- - scheduler;
-- - Supabase Cron;
-- - backend;
-- - proceso administrativo.
--
-- Por ahora no programamos ninguna ejecución automática porque
-- todavía no hemos definido/activado el mecanismo de scheduler.
-- ============================================================

CREATE OR REPLACE FUNCTION public.evaluar_asignaciones_pendientes()
RETURNS TABLE (
    asignacion_id uuid,
    estado_resultante varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_asignacion record;
BEGIN

    FOR v_asignacion IN

        SELECT
            a.id
        FROM public.asignaciones a
        JOIN public.estados_asignacion ea
            ON ea.id = a.estado_id
        WHERE a.activo = true
          AND a.deleted_at IS NULL
          AND ea.codigo IN (
              'PENDIENTE',
              'CONFIRMADA'
          )

    LOOP

        asignacion_id := v_asignacion.id;

        estado_resultante :=
            public.evaluar_estado_asignacion(
                v_asignacion.id
            );

        RETURN NEXT;

    END LOOP;

END;
$$;


COMMENT ON FUNCTION public.evaluar_asignaciones_pendientes() IS
'Evalúa todas las asignaciones activas PENDIENTE o CONFIRMADA para determinar si deben pasar a REALIZADA o NO_REALIZADA.';


COMMIT;