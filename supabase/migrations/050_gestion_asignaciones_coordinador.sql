-- Complemento idempotente para instalaciones que ya ejecutaron 049.
BEGIN;
INSERT INTO public.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE r.codigo='COORDINADOR' AND p.activo
AND p.codigo IN ('UPDATE_ASSIGNMENT','CANCEL_ASSIGNMENT','REASSIGN_ASSIGNMENT')
ON CONFLICT(rol_id,permiso_id) DO NOTHING;
COMMIT;
