-- Verificación estructural de la migración 059.
BEGIN;
DO $$
BEGIN
  IF to_regprocedure('public.validate_asignacion_tipo_actividad()') IS NULL THEN
    RAISE EXCEPTION 'Falta validate_asignacion_tipo_actividad';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='asignaciones' AND column_name='sala_id') THEN
    RAISE EXCEPTION 'sala_id histórico debe conservarse';
  END IF;
END $$;
ROLLBACK;
