-- ============================================================
-- Migration 016
-- Scheduler automático para ciclo de vida de asignaciones
--
-- Objetivo:
-- Ejecutar periódicamente la evaluación automática de las
-- asignaciones activas que todavía requieren resolución.
--
-- Frecuencia MVP:
-- Cada 15 minutos.
--
-- Reglas procesadas por:
-- public.evaluar_asignaciones_pendientes()
--
-- IMPORTANTE:
-- pg_cron debe estar habilitado en el proyecto Supabase.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
    v_job_id bigint;
BEGIN
    -- Evita duplicar el scheduler si la migración se vuelve
    -- a ejecutar en un ambiente donde el job ya existe.
    SELECT jobid
    INTO v_job_id
    FROM cron.job
    WHERE jobname = 'evaluar_ciclo_vida_asignaciones'
    LIMIT 1;

    IF v_job_id IS NOT NULL THEN
        PERFORM cron.unschedule(v_job_id);
    END IF;
END;
$$;

SELECT cron.schedule(
    'evaluar_ciclo_vida_asignaciones',
    '*/15 * * * *',
    $cron$
        SELECT *
        FROM public.evaluar_asignaciones_pendientes();
    $cron$
);