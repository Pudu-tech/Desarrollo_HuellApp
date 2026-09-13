-- ============================================================
-- HuellAPP
-- Migración 009
-- Agrega permiso para reactivar salas.
--
-- Objetivo:
--   Incorporar el permiso ACTIVATE_ROOM al sistema RBAC,
--   permitiendo reactivar salas previamente desactivadas.
--
-- Roles autorizados:
--   - SUPERADMIN
--   - DIRECTIVA
--
-- Notas:
--   - El script es idempotente:
--     puede ejecutarse más de una vez sin duplicar registros.
--   - No modifica permisos existentes.
--   - No asigna este permiso a COORDINADOR ni MONITOR.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. CREAR PERMISO ACTIVATE_ROOM
-- ============================================================
--
-- Se crea únicamente si todavía no existe un permiso
-- con el mismo código.
-- ============================================================

INSERT INTO public.permisos (
    codigo,
    nombre,
    descripcion,
    modulo,
    activo
)
SELECT
    'ACTIVATE_ROOM',
    'Activar salas',
    'Permite reactivar salas previamente desactivadas.',
    'SALAS',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.permisos
    WHERE codigo = 'ACTIVATE_ROOM'
);


-- ============================================================
-- 2. ASIGNAR PERMISO A SUPERADMIN Y DIRECTIVA
-- ============================================================
--
-- Se relaciona ACTIVATE_ROOM únicamente con los roles:
--   - SUPERADMIN
--   - DIRECTIVA
--
-- NOT EXISTS evita duplicar asociaciones en rol_permiso.
-- ============================================================

INSERT INTO public.rol_permiso (
    rol_id,
    permiso_id
)
SELECT
    r.id,
    p.id
FROM public.roles AS r
CROSS JOIN public.permisos AS p
WHERE r.codigo IN (
    'SUPERADMIN',
    'DIRECTIVA'
)
AND p.codigo = 'ACTIVATE_ROOM'
AND NOT EXISTS (
    SELECT 1
    FROM public.rol_permiso AS rp
    WHERE rp.rol_id = r.id
      AND rp.permiso_id = p.id
);


COMMIT;

-- ============================================================
-- VERIFICACIÓN MANUAL
-- ============================================================
-- Ejecutar después de aplicar la migración si se desea validar:
--
-- SELECT
--     r.codigo AS rol,
--     p.codigo AS permiso
-- FROM public.rol_permiso rp
-- JOIN public.roles r
--     ON r.id = rp.rol_id
-- JOIN public.permisos p
--     ON p.id = rp.permiso_id
-- WHERE p.codigo = 'ACTIVATE_ROOM'
-- ORDER BY r.codigo;
--
-- Resultado esperado:
--
-- DIRECTIVA   | ACTIVATE_ROOM
-- SUPERADMIN  | ACTIVATE_ROOM
-- ============================================================