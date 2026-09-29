-- ============================================================
-- HuellAPP
-- Migración 036
-- Permitir eliminación definitiva de identidades en Supabase Auth
-- conservando el registro histórico en public.usuarios.
--
-- REGLA FUNCIONAL
-- ------------------------------------------------------------
-- DESACTIVAR:
--   - conserva public.usuarios
--   - conserva auth.users
--   - permite reactivación posterior
--
-- ELIMINAR:
--   - conserva public.usuarios como registro histórico
--   - marca deleted_at y activo = false
--   - conserva auditoría
--   - elimina definitivamente auth.users
-- ============================================================

BEGIN;

ALTER TABLE public.usuarios
DROP CONSTRAINT IF EXISTS fk_usuarios_auth;

COMMENT ON COLUMN public.usuarios.id IS
'UUID histórico del usuario. Durante la vida activa coincide con '
'el UUID de auth.users. Tras una eliminación definitiva de la '
'identidad Auth, el registro se conserva para trazabilidad, '
'auditoría y referencias históricas.';

COMMIT;