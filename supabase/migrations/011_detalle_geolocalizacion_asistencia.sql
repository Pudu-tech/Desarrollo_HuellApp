-- ============================================================
-- HuellAPP
-- Migración 011
-- Detalle legible de geolocalización en asistencias
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Complementar las coordenadas GPS almacenadas en
-- asistencias_asignacion con información legible obtenida
-- mediante reverse geocoding.
--
-- IMPORTANTE
-- ------------------------------------------------------------
-- La evidencia principal de ubicación continúa siendo:
--
--   - latitud
--   - longitud
--   - precision_metros
--   - fecha_geolocalizacion
--
-- comuna_detectada, region_detectada y direccion_detectada
-- son datos informativos derivados de las coordenadas.
--
-- Estos valores NO deben ser utilizados como reemplazo
-- de las coordenadas GPS originales.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. COMUNA DETECTADA
-- ============================================================

ALTER TABLE public.asistencias_asignacion
ADD COLUMN IF NOT EXISTS comuna_detectada varchar(150);


COMMENT ON COLUMN public.asistencias_asignacion.comuna_detectada IS
'Comuna aproximada obtenida mediante reverse geocoding de las coordenadas GPS. Dato informativo.';


-- ============================================================
-- 2. REGIÓN DETECTADA
-- ============================================================

ALTER TABLE public.asistencias_asignacion
ADD COLUMN IF NOT EXISTS region_detectada varchar(150);


COMMENT ON COLUMN public.asistencias_asignacion.region_detectada IS
'Región aproximada obtenida mediante reverse geocoding de las coordenadas GPS. Dato informativo.';


-- ============================================================
-- 3. DOCUMENTAR DIRECCIÓN DETECTADA EXISTENTE
-- ============================================================

COMMENT ON COLUMN public.asistencias_asignacion.direccion_detectada IS
'Dirección aproximada obtenida mediante reverse geocoding. Puede contener calle, numeración u otra referencia disponible. Dato informativo.';


-- ============================================================
-- 4. DOCUMENTAR DATOS GPS PRINCIPALES
-- ============================================================

COMMENT ON COLUMN public.asistencias_asignacion.latitud IS
'Latitud registrada por el dispositivo al informar asistencia. Evidencia principal de geolocalización.';


COMMENT ON COLUMN public.asistencias_asignacion.longitud IS
'Longitud registrada por el dispositivo al informar asistencia. Evidencia principal de geolocalización.';


COMMENT ON COLUMN public.asistencias_asignacion.precision_metros IS
'Precisión aproximada de la geolocalización reportada por el dispositivo, expresada en metros.';


COMMENT ON COLUMN public.asistencias_asignacion.fecha_geolocalizacion IS
'Fecha y hora en que el dispositivo obtuvo la ubicación utilizada para registrar la asistencia.';


COMMIT;