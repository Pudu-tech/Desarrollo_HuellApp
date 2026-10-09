-- DEV/QA después de 049. Solo lectura; no envía correos.
BEGIN;
DO $$
BEGIN
 ASSERT NOT EXISTS(SELECT 1 FROM public.roles r CROSS JOIN public.permisos p
  WHERE r.codigo IN ('SUPERADMIN','DIRECTIVA') AND p.activo
  AND NOT EXISTS(SELECT 1 FROM public.rol_permiso rp WHERE rp.rol_id=r.id AND rp.permiso_id=p.id)),
  'Administradores sin permisos activos';
 ASSERT NOT EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.roles r ON r.id=rp.rol_id
  JOIN public.permisos p ON p.id=rp.permiso_id WHERE r.codigo='COORDINADOR'
  AND p.codigo NOT IN ('VIEW_ASSIGNMENTS','CREATE_ASSIGNMENT','CREATE_TRAINING','CREATE_CENTRAL_EVENT','UPDATE_ASSIGNMENT','CANCEL_ASSIGNMENT','REASSIGN_ASSIGNMENT',
   'ACCEPT_PARTICIPATION','REJECT_PARTICIPATION','REPORT_ATTENDANCE')), 'Coordinador tiene permisos adicionales';
 ASSERT (SELECT count(*)=10 FROM public.rol_permiso rp JOIN public.roles r ON r.id=rp.rol_id
  JOIN public.permisos p ON p.id=rp.permiso_id WHERE r.codigo='COORDINADOR' AND p.activo), 'Faltan permisos de coordinador';
 ASSERT NOT EXISTS(SELECT 1 FROM public.rol_permiso rp JOIN public.roles r ON r.id=rp.rol_id
  JOIN public.permisos p ON p.id=rp.permiso_id WHERE r.codigo='MONITOR'
  AND p.codigo NOT IN ('VIEW_ASSIGNMENTS','ACCEPT_PARTICIPATION','REJECT_PARTICIPATION','REPORT_ATTENDANCE')),
  'Monitor tiene permisos de gestión';
 ASSERT (SELECT count(*)=4 FROM public.rol_permiso rp JOIN public.roles r ON r.id=rp.rol_id
  JOIN public.permisos p ON p.id=rp.permiso_id WHERE r.codigo='MONITOR' AND p.activo), 'Faltan permisos de monitor';
 RAISE NOTICE '049: matriz de roles aprobada';
END;
$$;
ROLLBACK;
