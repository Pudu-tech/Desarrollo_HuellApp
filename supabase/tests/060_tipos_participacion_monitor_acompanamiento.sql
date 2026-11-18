-- Verificación de migración 060.
BEGIN;

DO $$
DECLARE
    v_activos text[];
    v_def text;
BEGIN
    SELECT array_agg(codigo ORDER BY codigo)
    INTO v_activos
    FROM public.tipos_participacion
    WHERE activo = true;

    IF v_activos IS DISTINCT FROM ARRAY['ACOMPANAMIENTO','MONITOR']::text[] THEN
        RAISE EXCEPTION 'Tipos activos inesperados: %', v_activos;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.tipos_participacion
        WHERE codigo IN ('RELATOR','OBSERVADOR') AND activo = true
    ) THEN
        RAISE EXCEPTION 'RELATOR/OBSERVADOR deben quedar inactivos.';
    END IF;

    SELECT pg_get_functiondef(p.oid)
    INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'aceptar_participacion_atomica'
    ORDER BY p.oid DESC
    LIMIT 1;

    IF v_def IS NULL OR position('MONITOR' in v_def) = 0 THEN
        RAISE EXCEPTION 'La RPC aceptar_participacion_atomica no reconoce MONITOR.';
    END IF;
END $$;

ROLLBACK;
