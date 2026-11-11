-- HuellApp · gestion asignaciones coordinador.
--
-- RESPONSABILIDADES
-- ------------------------------------------------------------
-- - Verificar las reglas de gestion asignaciones coordinador con los casos SQL del archivo.
--
-- ESTADO ACTUAL
-- ------------------------------------------------------------
-- - Prueba de base de datos con sus fixtures y transacción de verificación.
--
-- SECURITY
-- ------------------------------------------------------------
-- Revisar los requisitos de datos antes de ejecutar en DEV/QA; no utilizar producción.

-- Después de 050. Solo lectura, sin correos.
BEGIN;
DO $$
BEGIN
 ASSERT (SELECT count(*)=3 FROM public.roles r JOIN public.rol_permiso rp ON rp.rol_id=r.id
  JOIN public.permisos p ON p.id=rp.permiso_id WHERE r.codigo='COORDINADOR' AND p.activo
  AND p.codigo IN ('UPDATE_ASSIGNMENT','CANCEL_ASSIGNMENT','REASSIGN_ASSIGNMENT')),
  'Faltan permisos de gestión de asignaciones para coordinador';
 ASSERT NOT EXISTS(SELECT 1 FROM public.roles r JOIN public.rol_permiso rp ON rp.rol_id=r.id
  JOIN public.permisos p ON p.id=rp.permiso_id WHERE r.codigo='MONITOR'
  AND p.codigo IN ('UPDATE_ASSIGNMENT','CANCEL_ASSIGNMENT','REASSIGN_ASSIGNMENT')),
  'Monitor no debe administrar asignaciones';
 RAISE NOTICE '050: gestión de coordinador aprobada';
END;
$$;
ROLLBACK;
