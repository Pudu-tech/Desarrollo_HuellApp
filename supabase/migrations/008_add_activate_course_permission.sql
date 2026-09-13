-- ============================================================
-- HuellAPP
-- Migración 008
-- Agrega permiso para reactivar cursos.
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
    'ACTIVATE_COURSE',
    'Activar cursos',
    'Permite reactivar cursos previamente desactivados.',
    'CURSOS',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.permisos
    WHERE codigo = 'ACTIVATE_COURSE'
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
  AND p.codigo = 'ACTIVATE_COURSE'
  AND NOT EXISTS (
      SELECT 1
      FROM public.rol_permiso rp
      WHERE rp.rol_id = r.id
        AND rp.permiso_id = p.id
  );

COMMIT;
