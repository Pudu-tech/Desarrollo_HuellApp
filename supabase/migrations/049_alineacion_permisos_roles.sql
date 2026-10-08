-- HuellApp: matriz de roles acordada. Ejecutar después de 048.
-- La autorización de RPC y API continúa basada en rol_permiso.
BEGIN;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.roles WHERE codigo IN ('SUPERADMIN','DIRECTIVA','COORDINADOR','MONITOR')) <> 4 THEN
  RAISE EXCEPTION 'Faltan roles de HuellApp';
 END IF;
END;
$$;

-- Administración completa. La prohibición de crear SUPERADMIN desde DIRECTIVA
-- se conserva en crear_usuario_atomico y en la API; no existe un permiso separado.
INSERT INTO public.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE r.codigo IN ('SUPERADMIN','DIRECTIVA') AND p.activo
ON CONFLICT(rol_id,permiso_id) DO NOTHING;

-- COORDINADOR ve, crea, edita, cancela y reasigna actividades de todos los tipos. Además responde
-- sus invitaciones y registra su propia asistencia, sin administrar terceros.
DELETE FROM public.rol_permiso rp USING public.roles r, public.permisos p
WHERE rp.rol_id=r.id AND rp.permiso_id=p.id AND r.codigo='COORDINADOR'
AND p.codigo NOT IN ('VIEW_ASSIGNMENTS','CREATE_ASSIGNMENT','CREATE_TRAINING','CREATE_CENTRAL_EVENT','UPDATE_ASSIGNMENT','CANCEL_ASSIGNMENT','REASSIGN_ASSIGNMENT',
 'ACCEPT_PARTICIPATION','REJECT_PARTICIPATION','REPORT_ATTENDANCE');
INSERT INTO public.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE r.codigo='COORDINADOR' AND p.activo AND p.codigo IN
 ('VIEW_ASSIGNMENTS','CREATE_ASSIGNMENT','CREATE_TRAINING','CREATE_CENTRAL_EVENT','UPDATE_ASSIGNMENT','CANCEL_ASSIGNMENT','REASSIGN_ASSIGNMENT',
  'ACCEPT_PARTICIPATION','REJECT_PARTICIPATION','REPORT_ATTENDANCE')
ON CONFLICT(rol_id,permiso_id) DO NOTHING;

-- MONITOR solo consulta asignaciones propias y responde/informa su asistencia.
-- Las consultas de asignaciones ya limitan sus resultados al usuario autenticado.
DELETE FROM public.rol_permiso rp USING public.roles r, public.permisos p
WHERE rp.rol_id=r.id AND rp.permiso_id=p.id AND r.codigo='MONITOR'
AND p.codigo NOT IN ('VIEW_ASSIGNMENTS','ACCEPT_PARTICIPATION','REJECT_PARTICIPATION','REPORT_ATTENDANCE');
INSERT INTO public.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permisos p
WHERE r.codigo='MONITOR' AND p.activo AND p.codigo IN
 ('VIEW_ASSIGNMENTS','ACCEPT_PARTICIPATION','REJECT_PARTICIPATION','REPORT_ATTENDANCE')
ON CONFLICT(rol_id,permiso_id) DO NOTHING;
COMMIT;
