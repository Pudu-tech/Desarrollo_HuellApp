-- ============================================================
-- HuellAPP
-- Migración 035
-- Hardening de funciones automáticas de ciclo de vida
-- ============================================================
--
-- Hallazgo:
-- evaluar_estado_asignacion(uuid) y
-- evaluar_asignaciones_pendientes()
-- son SECURITY DEFINER y actualmente heredaron EXECUTE para
-- PUBLIC, anon y authenticated.
--
-- Esta migración restringe su ejecución a service_role.
-- El owner postgres conserva sus privilegios, por lo que un
-- pg_cron ejecutado como postgres no pierde acceso.
-- ============================================================

BEGIN;

REVOKE ALL ON FUNCTION public.evaluar_estado_asignacion(uuid)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.evaluar_estado_asignacion(uuid)
FROM anon;

REVOKE ALL ON FUNCTION public.evaluar_estado_asignacion(uuid)
FROM authenticated;

GRANT EXECUTE ON FUNCTION public.evaluar_estado_asignacion(uuid)
TO service_role;


REVOKE ALL ON FUNCTION public.evaluar_asignaciones_pendientes()
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.evaluar_asignaciones_pendientes()
FROM anon;

REVOKE ALL ON FUNCTION public.evaluar_asignaciones_pendientes()
FROM authenticated;

GRANT EXECUTE ON FUNCTION public.evaluar_asignaciones_pendientes()
TO service_role;

COMMIT;
