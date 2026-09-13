-- ============================================================
-- HuellAPP
-- Migración 007
-- Agrega permiso para reactivar colegios.
-- ============================================================

BEGIN;

INSERT INTO public.permisos (
    codigo,
    nombre,
    descripcion,
    modulo,
    activo
)
SELECT
    'ACTIVATE_SCHOOL',
    'Activar colegios',
    'Permite reactivar colegios previamente desactivados.',
    'COLEGIOS',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.permisos
    WHERE codigo = 'ACTIVATE_SCHOOL'
);

INSERT INTO public.rol_permiso (
    rol_id,
    permiso_id
)
SELECT
    r.id,
    p.id
FROM public.roles r
CROSS JOIN public.permisos p
WHERE r.codigo IN ('SUPERADMIN', 'DIRECTIVA')
  AND p.codigo = 'ACTIVATE_SCHOOL'
  AND NOT EXISTS (
      SELECT 1
      FROM public.rol_permiso rp
      WHERE rp.rol_id = r.id
        AND rp.permiso_id = p.id
  );

COMMIT;
