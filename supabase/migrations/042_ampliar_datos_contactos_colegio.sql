/* ============================================================
   HuellAPP | Migración 042
   Ampliación no destructiva de datos personales de contactos

   OBJETIVO
   ------------------------------------------------------------
   - Conservar los contactos existentes y sus relaciones con
     asignacion_contactos sin modificar sus identificadores.
   - Incorporar apellidos separados y RUT opcional.
   - Mantener compatibilidad con los endpoints y formularios
     existentes mientras se realiza la transición.

   REGLAS
   ------------------------------------------------------------
   - La columna nombre existente NO se modifica ni se divide
     automáticamente: podría contener nombres y apellidos.
   - Los nuevos apellidos quedan temporalmente opcionales
     para no invalidar registros previos.
   - El RUT es opcional; un valor vacío no se almacena.
   - Esta migración NO crea, edita ni elimina contactos.
   - Las altas, modificaciones y bajas futuras deberán usar
     las operaciones auditadas que se implementarán después.

   EJECUCIÓN
   ------------------------------------------------------------
   - Respaldar la base de datos DEV antes de ejecutar.
   - Ejecutar una sola vez y verificar los resultados.
   ============================================================ */

BEGIN;

/* ============================================================
   1. EXTENSIÓN DEL MODELO ACTUAL
   ============================================================ */

ALTER TABLE public.contactos_colegio
    ADD COLUMN IF NOT EXISTS apellido_paterno varchar,
    ADD COLUMN IF NOT EXISTS apellido_materno varchar,
    ADD COLUMN IF NOT EXISTS rut varchar;

COMMENT ON COLUMN public.contactos_colegio.nombre IS
    'Nombre existente del contacto. En registros anteriores puede contener nombre completo; revisar antes de separar.';
COMMENT ON COLUMN public.contactos_colegio.apellido_paterno IS
    'Apellido paterno del contacto. Permanece opcional hasta normalizar contactos históricos.';
COMMENT ON COLUMN public.contactos_colegio.apellido_materno IS
    'Apellido materno del contacto, opcional.';
COMMENT ON COLUMN public.contactos_colegio.rut IS
    'RUT del contacto, opcional. Validación de formato y dígito verificador pendiente de la capa de negocio.';

/* ============================================================
   2. RESTRICCIONES NO DESTRUCTIVAS
   ============================================================ */

-- Los apellidos informados no pueden consistir solo en espacios.
-- Los registros históricos NULL siguen siendo válidos.
ALTER TABLE public.contactos_colegio
    ADD CONSTRAINT chk_contactos_colegio_apellido_paterno_no_vacio
        CHECK (apellido_paterno IS NULL OR btrim(apellido_paterno) <> ''),
    ADD CONSTRAINT chk_contactos_colegio_apellido_materno_no_vacio
        CHECK (apellido_materno IS NULL OR btrim(apellido_materno) <> ''),
    ADD CONSTRAINT chk_contactos_colegio_rut_no_vacio
        CHECK (rut IS NULL OR btrim(rut) <> '');

COMMIT;
