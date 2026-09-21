-- ============================================================
-- HuellAPP
-- Migración 015
-- Auditoría e historial para ciclo de vida automático
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Registrar correctamente las transiciones automáticas:
--
--   PENDIENTE / CONFIRMADA
--          ↓
--      REALIZADA
--
--   PENDIENTE / CONFIRMADA
--          ↓
--    NO_REALIZADA
--
-- Las transiciones automáticas:
--
-- - NO poseen usuario actor;
-- - utilizan origen/source = SYSTEM;
-- - dejan updated_by = NULL;
-- - generan registro en historial_asignacion;
-- - generan registro en audit_logs.
--
-- No se crea un usuario ficticio "SYSTEM".
--
-- Las transiciones humanas continúan utilizando el usuario
-- autenticado real desde FastAPI.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. PERMITIR HISTORIAL SIN ACTOR HUMANO
-- ============================================================
--
-- Actualmente usuario_actor_id es NOT NULL.
-- Para procesos automáticos debe poder ser NULL.
-- ============================================================

ALTER TABLE public.historial_asignacion
ALTER COLUMN usuario_actor_id DROP NOT NULL;


COMMENT ON COLUMN
public.historial_asignacion.usuario_actor_id IS
'Usuario que ejecutó la acción. NULL cuando la transición fue realizada automáticamente por el sistema.';


COMMENT ON COLUMN
public.historial_asignacion.origen IS
'Origen de la acción. Ejemplos: WEB para acciones humanas y SYSTEM para procesos automáticos.';


COMMENT ON COLUMN
public.audit_logs.source IS
'Origen del evento auditado. Ejemplos: WEB para acciones humanas y SYSTEM para procesos automáticos.';


-- ============================================================
-- 2. REEMPLAZAR FUNCIÓN DE EVALUACIÓN
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

    v_nuevo_estado_id uuid;
    v_nuevo_estado_codigo varchar;

    v_fin_actividad timestamptz;

    v_tiene_presente boolean := false;

    v_accion varchar;
    v_descripcion text;
BEGIN

    -- --------------------------------------------------------
    -- OBTENER ASIGNACIÓN
    -- --------------------------------------------------------

    SELECT
        a.id,
        a.fecha,
        a.hora_inicio,
        a.hora_fin,
        a.estado_id,
        a.activo,
        a.deleted_at,
        a.updated_at,
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


    -- --------------------------------------------------------
    -- ASIGNACIONES NO OPERATIVAS
    -- --------------------------------------------------------

    IF v_asignacion.deleted_at IS NOT NULL
       OR v_asignacion.activo IS NOT TRUE THEN

        RETURN v_asignacion.estado_codigo;

    END IF;


    v_estado_actual := v_asignacion.estado_codigo;


    -- --------------------------------------------------------
    -- ESTADOS CERRADOS
    -- --------------------------------------------------------
    --
    -- NO_REALIZADA puede posteriormente pasar a REALIZADA,
    -- pero solamente mediante regularización administrativa
    -- desde FastAPI. No mediante este proceso automático.
    -- --------------------------------------------------------

    IF v_estado_actual IN (
        'CANCELADA',
        'REALIZADA',
        'NO_REALIZADA'
    ) THEN

        RETURN v_estado_actual;

    END IF;


    -- --------------------------------------------------------
    -- CALCULAR TÉRMINO REAL DE LA ACTIVIDAD
    -- --------------------------------------------------------
    --
    -- Las fechas/horas de HuellAPP representan horario local
    -- de Chile.
    --
    -- America/Santiago contempla automáticamente cambios entre
    -- horario de verano e invierno.
    -- --------------------------------------------------------

    v_fin_actividad :=
        (
            v_asignacion.fecha
            + v_asignacion.hora_fin
        )
        AT TIME ZONE 'America/Santiago';


    -- --------------------------------------------------------
    -- TODAVÍA NO TERMINA
    -- --------------------------------------------------------

    IF CURRENT_TIMESTAMP <= v_fin_actividad THEN
        RETURN v_estado_actual;
    END IF;


    -- --------------------------------------------------------
    -- ¿EXISTE AL MENOS UNA ASISTENCIA PRESENTE?
    -- --------------------------------------------------------
    --
    -- Se incluyen participaciones históricas porque la asistencia
    -- registrada sigue siendo evidencia de que la actividad ocurrió.
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


    -- ========================================================
    -- 3. DETERMINAR NUEVO ESTADO
    -- ========================================================

    IF v_tiene_presente THEN

        -- ----------------------------------------------------
        -- TERMINÓ + PRESENTE = REALIZADA
        -- ----------------------------------------------------

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


        v_nuevo_estado_id := v_estado_realizada_id;
        v_nuevo_estado_codigo := 'REALIZADA';

        v_accion := 'AUTO_COMPLETE_ASSIGNMENT';

        v_descripcion :=
            'Asignación marcada automáticamente como REALIZADA '
            'porque terminó su horario y existe al menos una '
            'asistencia PRESENTE.';


    ELSIF CURRENT_TIMESTAMP >= (
        v_fin_actividad + interval '24 hours'
    ) THEN

        -- ----------------------------------------------------
        -- +24 HORAS SIN PRESENTE = NO_REALIZADA
        -- ----------------------------------------------------

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


        v_nuevo_estado_id := v_estado_no_realizada_id;
        v_nuevo_estado_codigo := 'NO_REALIZADA';

        v_accion := 'AUTO_MARK_NOT_COMPLETED';

        v_descripcion :=
            'Asignación marcada automáticamente como NO_REALIZADA '
            'porque transcurrieron 24 horas desde su término sin '
            'registrarse ninguna asistencia PRESENTE.';


    ELSE

        -- ----------------------------------------------------
        -- TERMINÓ, PERO SIGUE DENTRO DE LAS 24 HORAS
        -- ----------------------------------------------------

        RETURN v_estado_actual;

    END IF;


    -- ========================================================
    -- 4. ACTUALIZAR ESTADO
    -- ========================================================
    --
    -- La comparación con el estado anterior funciona como una
    -- protección básica contra actualizaciones concurrentes.
    --
    -- updated_by queda NULL porque no existe actor humano.
    -- ========================================================

    UPDATE public.asignaciones
    SET
        estado_id = v_nuevo_estado_id,
        updated_by = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_asignacion_id
      AND estado_id = v_asignacion.estado_id;


    -- Si otra operación cambió el estado antes que nosotros,
    -- no registramos una transición que realmente no ocurrió.
    IF NOT FOUND THEN

        SELECT ea.codigo
        INTO v_estado_actual
        FROM public.asignaciones a
        JOIN public.estados_asignacion ea
            ON ea.id = a.estado_id
        WHERE a.id = p_asignacion_id;

        RETURN v_estado_actual;

    END IF;


    -- ========================================================
    -- 5. HISTORIAL DE ASIGNACIÓN
    -- ========================================================

    INSERT INTO public.historial_asignacion (
        asignacion_id,
        accion,
        estado_anterior_id,
        estado_nuevo_id,
        motivo,
        usuario_actor_id,
        origen
    )
    VALUES (
        p_asignacion_id,
        v_accion,
        v_asignacion.estado_id,
        v_nuevo_estado_id,
        v_descripcion,
        NULL,
        'SYSTEM'
    );


    -- ========================================================
    -- 6. AUDITORÍA GENERAL
    -- ========================================================
    --
    -- actor_user_id y actor_role_id quedan NULL porque el evento
    -- fue generado por el sistema.
    --
    -- request_id también queda NULL porque no existe una petición
    -- HTTP asociada a una futura ejecución por scheduler.
    -- ========================================================

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
        NULL,
        NULL,
        v_accion,
        'ASSIGNMENT',
        p_asignacion_id,

        jsonb_build_object(
            'estado_id',
            v_asignacion.estado_id,
            'estado',
            v_asignacion.estado_codigo
        ),

        jsonb_build_object(
            'estado_id',
            v_nuevo_estado_id,
            'estado',
            v_nuevo_estado_codigo
        ),

        v_descripcion,

        NULL,
        NULL,
        NULL,
        'SYSTEM'
    );


    RETURN v_nuevo_estado_codigo;

END;
$$;


COMMENT ON FUNCTION
public.evaluar_estado_asignacion(uuid) IS
'Evalúa el ciclo de vida automático de una asignación y registra las transiciones REALIZADA o NO_REALIZADA tanto en historial_asignacion como en audit_logs con origen SYSTEM.';


-- ============================================================
-- 7. FUNCIÓN MASIVA
-- ============================================================
--
-- Se redefine para mantener la implementación documentada junto
-- al nuevo comportamiento de evaluar_estado_asignacion().
--
-- Aún NO se configura cron/scheduler en esta migración.
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


COMMENT ON FUNCTION
public.evaluar_asignaciones_pendientes() IS
'Evalúa asignaciones activas PENDIENTE o CONFIRMADA y aplica su ciclo de vida automático con auditoría e historial SYSTEM.';


COMMIT;