BEGIN;

-- Estructura principal.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='asignaciones' AND column_name='coordinador_id'
    ) THEN
        RAISE EXCEPTION 'Falta asignaciones.coordinador_id';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname='fk_asignaciones_coordinador'
          AND conrelid='public.asignaciones'::regclass
    ) THEN
        RAISE EXCEPTION 'Falta FK de coordinador responsable';
    END IF;
END $$;

-- La nueva RPC de creación debe existir con coordinador explícito.
DO $$
BEGIN
    IF to_regprocedure('public.crear_asignacion_atomica(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,time,time,text,text,jsonb,jsonb,uuid,uuid,inet,text)') IS NULL THEN
        RAISE EXCEPTION 'No existe la RPC 061 de creación';
    END IF;
    IF to_regprocedure('public.actualizar_asignacion_atomica(uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text)') IS NULL THEN
        RAISE EXCEPTION 'No existe la RPC 061 de actualización';
    END IF;
END $$;

ROLLBACK;
