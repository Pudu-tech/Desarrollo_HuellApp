-- ============================================================
-- HuellAPP
-- Migración 013
-- Estado NO_REALIZADA para asignaciones
-- ============================================================
--
-- REGLA DE NEGOCIO:
--
-- Una asignación pasa a:
--
--   REALIZADA
--   si ya terminó su horario y existe al menos una asistencia PRESENTE.
--
--   NO_REALIZADA
--   si han transcurrido 24 horas desde el término de la asignación
--   y no existe ninguna asistencia PRESENTE.
--
-- NO_REALIZADA:
-- - representa una actividad que no pudo acreditarse como realizada
--   dentro de las 24 horas posteriores a su término;
-- - solo DIRECTIVA y SUPERADMIN podrán regularizar posteriormente;
-- - una regularización administrativa que deje al menos una asistencia
--   PRESENTE podrá llevar la asignación a REALIZADA;
-- - toda transición deberá quedar registrada en auditoría.
--
-- El campo "orden" es obligatorio en estados_asignacion.
-- Se utiliza MAX(orden) + 1 para evitar depender de un valor fijo.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. AGREGAR ESTADO NO_REALIZADA
-- ============================================================

INSERT INTO public.estados_asignacion (
    codigo,
    nombre,
    orden,
    activo
)
SELECT
    'NO_REALIZADA',
    'No realizada',
    COALESCE(MAX(orden), 0) + 1,
    true
FROM public.estados_asignacion
WHERE NOT EXISTS (
    SELECT 1
    FROM public.estados_asignacion
    WHERE codigo = 'NO_REALIZADA'
);


COMMIT;