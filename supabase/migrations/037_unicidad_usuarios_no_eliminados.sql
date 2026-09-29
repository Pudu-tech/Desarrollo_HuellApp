-- ============================================================
-- HuellAPP
-- Migración 037
-- Unicidad de RUT y correo solamente para usuarios no eliminados
-- ============================================================
--
-- REGLA FUNCIONAL
-- ------------------------------------------------------------
-- Un usuario activo o desactivado conserva su RUT y correo.
--
-- Un usuario eliminado lógicamente:
--   deleted_at IS NOT NULL
--
-- deja libres su RUT y correo para que puedan ser utilizados
-- nuevamente por una identidad nueva.
--
-- Los registros históricos eliminados permanecen en
-- public.usuarios para trazabilidad y auditoría.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. ELIMINAR RESTRICCIONES UNIQUE GLOBALES
-- ============================================================
--
-- Estas restricciones actuales consideran también los registros
-- eliminados lógicamente, por lo que impiden reutilizar RUT/email.
-- ============================================================

ALTER TABLE public.usuarios
DROP CONSTRAINT IF EXISTS usuarios_email_key;

ALTER TABLE public.usuarios
DROP CONSTRAINT IF EXISTS usuarios_rut_key;


-- ============================================================
-- 2. ELIMINAR ÍNDICES PREVIOS SI EXISTEN
-- ============================================================

DROP INDEX IF EXISTS public.uq_usuarios_email_no_eliminado;
DROP INDEX IF EXISTS public.uq_usuarios_rut_no_eliminado;


-- ============================================================
-- 3. CREAR UNICIDAD PARCIAL
-- ============================================================
--
-- Solo los usuarios cuyo deleted_at sea NULL participan
-- en la restricción de unicidad.
--
-- Así:
--
-- usuario eliminado:
--   ign.messina@gmail.com
--   deleted_at != NULL
--
-- no impide crear posteriormente:
--
-- nuevo usuario:
--   ign.messina@gmail.com
--   deleted_at = NULL
-- ============================================================

CREATE UNIQUE INDEX uq_usuarios_email_no_eliminado
ON public.usuarios (
    lower(email)
)
WHERE deleted_at IS NULL;


CREATE UNIQUE INDEX uq_usuarios_rut_no_eliminado
ON public.usuarios (
    rut
)
WHERE deleted_at IS NULL;


-- ============================================================
-- 4. DOCUMENTACIÓN
-- ============================================================

COMMENT ON INDEX public.uq_usuarios_email_no_eliminado IS
'Garantiza correo único únicamente entre usuarios no eliminados lógicamente.';

COMMENT ON INDEX public.uq_usuarios_rut_no_eliminado IS
'Garantiza RUT único únicamente entre usuarios no eliminados lógicamente.';


COMMIT;