-- ============================================================================
-- HuellAPP
-- Migración 010: Rediseño completo del módulo de asignaciones
-- Fecha: 2026-09-15
--
-- OBJETIVO
--   Reemplazar el modelo de asignación de un solo usuario por un modelo de
--   actividad + múltiples participantes, incorporando:
--     - Tipos de actividad.
--     - Participaciones individuales.
--     - Aceptación/rechazo por participante.
--     - Espacios de encuentro.
--     - Profesores/contactos por actividad escolar.
--     - Asistencia individual con geolocalización.
--     - Estados globales de asignación.
--     - Permisos específicos.
--
-- CONTEXTO
--   El módulo actual aún no contiene información productiva. Los registros
--   existentes de asignaciones son de prueba y pueden eliminarse.
--
-- IMPORTANTE
--   - Ejecutar primero en DEV/QA.
--   - No ejecutar manualmente en PROD.
--   - El backend deberá desplegarse coordinadamente con esta migración.
--   - SUPERADMIN puede administrar y crear cualquier actividad, pero nunca
--     puede ser participante.
-- ============================================================================

-- PRECHECK DE ESQUEMA
-- Esta versión fue contrastada con la introspección actual de HuellAPP:
-- permisos(codigo,nombre,descripcion,modulo,activo,created_at,updated_at),
-- roles(codigo,...), usuarios(rol_id,activo,deleted_at,...),
-- rol_permiso UNIQUE(rol_id,permiso_id), espacios_reflexion UNIQUE(id,ramo_id)
-- y la función public.set_updated_at() existente.
--
BEGIN;

-- ============================================================================
-- 1. LIMPIEZA DE DATOS DE PRUEBA RELACIONADOS CON ASIGNACIONES
-- ============================================================================
-- notificaciones.entidad_id no posee FK hacia asignaciones. Se eliminan
-- únicamente notificaciones explícitamente asociadas al módulo.
DELETE FROM public.notificacion_envios
WHERE notificacion_id IN (
    SELECT id
    FROM public.notificaciones
    WHERE entidad_tipo IN ('ASIGNACION', 'ASIGNACION_PARTICIPANTE')
);

DELETE FROM public.notificaciones
WHERE entidad_tipo IN ('ASIGNACION', 'ASIGNACION_PARTICIPANTE');

-- audit_logs NO se elimina: es append-only y conserva trazabilidad histórica.

-- ============================================================================
-- 2. ELIMINAR ESTRUCTURA ANTIGUA / POSIBLES RESTOS DEL NUEVO MODELO
-- ============================================================================
-- Orden inverso de dependencias.
-- Se evita CASCADE deliberadamente: si existe una dependencia externa no
-- contemplada, la migración debe fallar y hacer ROLLBACK en vez de borrar
-- objetos accidentalmente.
DROP TABLE IF EXISTS public.asistencias_asignacion;
DROP TABLE IF EXISTS public.asignacion_contactos;
DROP TABLE IF EXISTS public.contactos_colegio;
DROP TABLE IF EXISTS public.asignacion_participantes;
DROP TABLE IF EXISTS public.estados_participacion;
DROP TABLE IF EXISTS public.tipos_participacion;
DROP TABLE IF EXISTS public.historial_asignacion;
DROP TABLE IF EXISTS public.asignaciones;
DROP TABLE IF EXISTS public.estados_asignacion;
DROP TABLE IF EXISTS public.espacios_encuentro;
DROP TABLE IF EXISTS public.tipos_actividad;

-- ============================================================================
-- 3. CATÁLOGO: TIPOS DE ACTIVIDAD
-- ============================================================================
CREATE TABLE public.tipos_actividad (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo varchar NOT NULL UNIQUE,
    nombre varchar NOT NULL,
    descripcion text NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.tipos_actividad IS
'Catálogo de tipos de actividad que puede representar una asignación HuellAPP.';

INSERT INTO public.tipos_actividad (codigo, nombre, descripcion)
VALUES
    ('ESPACIO_REFLEXION', 'Espacio de Reflexión',
     'Actividad escolar asociada a un ramo y un espacio de reflexión.'),
    ('ESPACIO_ENCUENTRO', 'Espacio de Encuentro',
     'Actividad escolar asociada a un ramo y un espacio de encuentro.'),
    ('REUNION', 'Reunión',
     'Reunión asociada a un colegio. Curso y sala son opcionales.'),
    ('CAPACITACION', 'Capacitación',
     'Actividad no escolar creada por Directiva o SuperAdmin.'),
    ('EVENTO_CASA_CENTRAL', 'Evento Casa Central',
     'Evento no escolar realizado en Casa Central u otro lugar definido.');

-- ============================================================================
-- 4. CATÁLOGO: ESTADOS GLOBALES DE ASIGNACIÓN
-- ============================================================================
CREATE TABLE public.estados_asignacion (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo varchar NOT NULL UNIQUE,
    nombre varchar NOT NULL,
    descripcion text NULL,
    orden integer NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.estados_asignacion IS
'Estado global de una actividad. ACEPTADA/RECHAZADA pertenecen al participante, no a la asignación.';

INSERT INTO public.estados_asignacion
    (codigo, nombre, descripcion, orden)
VALUES
    ('PENDIENTE', 'Pendiente',
     'Actividad creada y aún sin al menos un relator aceptado.', 1),
    ('CONFIRMADA', 'Confirmada',
     'Existe al menos un relator con participación aceptada.', 2),
    ('REALIZADA', 'Realizada',
     'La actividad fue ejecutada.', 3),
    ('CANCELADA', 'Cancelada',
     'La actividad fue cancelada.', 4);

-- ============================================================================
-- 5. CATÁLOGO: ESPACIOS DE ENCUENTRO
-- ============================================================================
CREATE TABLE public.espacios_encuentro (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ramo_id uuid NOT NULL,
    nombre varchar NOT NULL,
    descripcion text NULL,
    orden integer NULL,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamptz NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    updated_by uuid NULL,

    CONSTRAINT fk_espacios_encuentro_ramo
        FOREIGN KEY (ramo_id)
        REFERENCES public.ramos(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_espacios_encuentro_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_espacios_encuentro_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL,

    CONSTRAINT uq_espacio_encuentro_ramo_nombre
        UNIQUE (ramo_id, nombre),

    -- Permite FK compuesta desde asignaciones y garantiza que el espacio
    -- seleccionado pertenezca al ramo indicado.
    CONSTRAINT uq_espacio_encuentro_id_ramo
        UNIQUE (id, ramo_id)
);

COMMENT ON TABLE public.espacios_encuentro IS
'Catálogo de espacios de encuentro asociados a un ramo.';

-- ============================================================================
-- 6. TABLA PRINCIPAL: ASIGNACIONES
-- ============================================================================
CREATE TABLE public.asignaciones (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    tipo_actividad_id uuid NOT NULL,

    -- Contexto escolar. Es NULL para actividades de Casa Central.
    colegio_id uuid NULL,
    curso_colegio_id uuid NULL,
    sala_id uuid NULL,

    -- Contexto académico. Solo aplica a Reflexión/Encuentro.
    ramo_id uuid NULL,
    espacio_reflexion_id uuid NULL,
    espacio_encuentro_id uuid NULL,

    fecha date NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL,

    -- Obligatorio únicamente para CAPACITACION y EVENTO_CASA_CENTRAL.
    lugar varchar NULL,
    observacion text NULL,

    -- Debe corresponder inicialmente a PENDIENTE. Se resuelve en backend
    -- porque el catálogo utiliza UUID y no se fija un UUID hardcodeado.
    estado_id uuid NOT NULL,

    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamptz NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    updated_by uuid NULL,

    CONSTRAINT chk_asignaciones_horas
        CHECK (hora_fin > hora_inicio),

    CONSTRAINT fk_asignaciones_tipo_actividad
        FOREIGN KEY (tipo_actividad_id)
        REFERENCES public.tipos_actividad(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_colegio
        FOREIGN KEY (colegio_id)
        REFERENCES public.colegios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_curso
        FOREIGN KEY (curso_colegio_id)
        REFERENCES public.cursos_colegio(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_sala
        FOREIGN KEY (sala_id)
        REFERENCES public.salas(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_ramo
        FOREIGN KEY (ramo_id)
        REFERENCES public.ramos(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_espacio_reflexion_ramo
        FOREIGN KEY (espacio_reflexion_id, ramo_id)
        REFERENCES public.espacios_reflexion(id, ramo_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_espacio_encuentro_ramo
        FOREIGN KEY (espacio_encuentro_id, ramo_id)
        REFERENCES public.espacios_encuentro(id, ramo_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_estado
        FOREIGN KEY (estado_id)
        REFERENCES public.estados_asignacion(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignaciones_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE public.asignaciones IS
'Actividad planificada en HuellAPP. Las personas se relacionan mediante asignacion_participantes.';

-- ============================================================================
-- 7. VALIDACIÓN DE CAMPOS SEGÚN TIPO DE ACTIVIDAD
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_asignacion_tipo_actividad()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tipo varchar;
    v_colegio_curso uuid;
    v_colegio_sala uuid;
BEGIN
    SELECT codigo
      INTO v_tipo
      FROM public.tipos_actividad
     WHERE id = NEW.tipo_actividad_id
       AND activo = true;

    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'El tipo de actividad no existe o está inactivo.';
    END IF;

    -- Validar pertenencia de curso y sala al colegio cuando estén informados.
    IF NEW.curso_colegio_id IS NOT NULL THEN
        SELECT colegio_id
          INTO v_colegio_curso
          FROM public.cursos_colegio
         WHERE id = NEW.curso_colegio_id;

        IF NEW.colegio_id IS NULL OR v_colegio_curso IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION 'El curso no pertenece al colegio de la asignación.';
        END IF;
    END IF;

    IF NEW.sala_id IS NOT NULL THEN
        SELECT colegio_id
          INTO v_colegio_sala
          FROM public.salas
         WHERE id = NEW.sala_id;

        IF NEW.colegio_id IS NULL OR v_colegio_sala IS DISTINCT FROM NEW.colegio_id THEN
            RAISE EXCEPTION 'La sala no pertenece al colegio de la asignación.';
        END IF;
    END IF;

    IF v_tipo = 'ESPACIO_REFLEXION' THEN
        IF NEW.colegio_id IS NULL
           OR NEW.curso_colegio_id IS NULL
           OR NEW.sala_id IS NULL
           OR NEW.ramo_id IS NULL
           OR NEW.espacio_reflexion_id IS NULL
           OR NEW.espacio_encuentro_id IS NOT NULL
           OR NEW.lugar IS NOT NULL THEN
            RAISE EXCEPTION
                'ESPACIO_REFLEXION requiere colegio, curso, sala, ramo y espacio de reflexión; no admite espacio de encuentro ni lugar.';
        END IF;

    ELSIF v_tipo = 'ESPACIO_ENCUENTRO' THEN
        IF NEW.colegio_id IS NULL
           OR NEW.curso_colegio_id IS NULL
           OR NEW.sala_id IS NULL
           OR NEW.ramo_id IS NULL
           OR NEW.espacio_encuentro_id IS NULL
           OR NEW.espacio_reflexion_id IS NOT NULL
           OR NEW.lugar IS NOT NULL THEN
            RAISE EXCEPTION
                'ESPACIO_ENCUENTRO requiere colegio, curso, sala, ramo y espacio de encuentro; no admite espacio de reflexión ni lugar.';
        END IF;

    ELSIF v_tipo = 'REUNION' THEN
        IF NEW.colegio_id IS NULL
           OR NEW.ramo_id IS NOT NULL
           OR NEW.espacio_reflexion_id IS NOT NULL
           OR NEW.espacio_encuentro_id IS NOT NULL
           OR NEW.lugar IS NOT NULL THEN
            RAISE EXCEPTION
                'REUNION requiere colegio; curso y sala son opcionales; no admite ramo, espacios ni lugar.';
        END IF;

    ELSIF v_tipo IN ('CAPACITACION', 'EVENTO_CASA_CENTRAL') THEN
        IF NEW.colegio_id IS NOT NULL
           OR NEW.curso_colegio_id IS NOT NULL
           OR NEW.sala_id IS NOT NULL
           OR NEW.ramo_id IS NOT NULL
           OR NEW.espacio_reflexion_id IS NOT NULL
           OR NEW.espacio_encuentro_id IS NOT NULL
           OR NEW.lugar IS NULL
           OR btrim(NEW.lugar) = '' THEN
            RAISE EXCEPTION
                'CAPACITACION/EVENTO_CASA_CENTRAL no admite datos escolares y requiere lugar.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Tipo de actividad no soportado: %', v_tipo;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asignacion_tipo_actividad() IS
'Valida coherencia de campos y pertenencia de curso/sala según el tipo de actividad.';

CREATE TRIGGER trg_validate_asignacion_tipo_actividad
BEFORE INSERT OR UPDATE ON public.asignaciones
FOR EACH ROW
EXECUTE FUNCTION public.validate_asignacion_tipo_actividad();

-- ============================================================================
-- 8. CATÁLOGO: TIPOS DE PARTICIPACIÓN
-- ============================================================================
CREATE TABLE public.tipos_participacion (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo varchar NOT NULL UNIQUE,
    nombre varchar NOT NULL,
    descripcion text NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.tipos_participacion IS
'Función que cumple un usuario dentro de una asignación. LOCUTOR no forma parte del modelo.';

INSERT INTO public.tipos_participacion (codigo, nombre, descripcion)
VALUES
    ('RELATOR', 'Relator',
     'Participante principal u oficial de la actividad.'),
    ('ACOMPANAMIENTO', 'Acompañamiento',
     'Participante que acompaña la ejecución de la actividad.'),
    ('OBSERVADOR', 'Observador',
     'Participante que asiste en calidad de observación.');

-- ============================================================================
-- 9. CATÁLOGO: ESTADOS DE PARTICIPACIÓN
-- ============================================================================
CREATE TABLE public.estados_participacion (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo varchar NOT NULL UNIQUE,
    nombre varchar NOT NULL,
    descripcion text NULL,
    orden integer NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.estados_participacion IS
'Estado individual de respuesta de un participante dentro de una asignación.';

INSERT INTO public.estados_participacion
    (codigo, nombre, descripcion, orden)
VALUES
    ('PENDIENTE', 'Pendiente',
     'Participante aún no responde la asignación.', 1),
    ('ACEPTADA', 'Aceptada',
     'Participante acepta su participación.', 2),
    ('RECHAZADA', 'Rechazada',
     'Participante rechaza su participación e informa motivo.', 3);

-- ============================================================================
-- 10. PARTICIPANTES DE ASIGNACIÓN
-- ============================================================================
CREATE TABLE public.asignacion_participantes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asignacion_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    tipo_participacion_id uuid NOT NULL,
    estado_participacion_id uuid NOT NULL,
    motivo_rechazo text NULL,
    fecha_respuesta timestamptz NULL,
    respondido_por uuid NULL,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamptz NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    updated_by uuid NULL,

    CONSTRAINT uq_asignacion_participante_usuario
        UNIQUE (asignacion_id, usuario_id),

    CONSTRAINT fk_asignacion_participantes_asignacion
        FOREIGN KEY (asignacion_id)
        REFERENCES public.asignaciones(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_asignacion_participantes_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_participantes_tipo
        FOREIGN KEY (tipo_participacion_id)
        REFERENCES public.tipos_participacion(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_participantes_estado
        FOREIGN KEY (estado_participacion_id)
        REFERENCES public.estados_participacion(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_participantes_respondido_por
        FOREIGN KEY (respondido_por)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_participantes_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_participantes_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE public.asignacion_participantes IS
'Usuarios que participan en una actividad. Un usuario solo puede aparecer una vez por asignación.';

-- Valida rol del participante y consistencia de su estado individual.
CREATE OR REPLACE FUNCTION public.validate_asignacion_participante()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_rol varchar;
    v_usuario_activo boolean;
    v_usuario_deleted_at timestamptz;
    v_estado varchar;
BEGIN
    SELECT r.codigo, u.activo, u.deleted_at
      INTO v_rol, v_usuario_activo, v_usuario_deleted_at
      FROM public.usuarios u
      JOIN public.roles r ON r.id = u.rol_id
     WHERE u.id = NEW.usuario_id;

    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'El usuario participante no existe.';
    END IF;

    IF v_usuario_activo IS NOT TRUE OR v_usuario_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'El usuario participante debe estar activo.';
    END IF;

    -- Regla de negocio: SUPERADMIN administra, pero nunca participa.
    IF v_rol NOT IN ('DIRECTIVA', 'COORDINADOR', 'MONITOR') THEN
        RAISE EXCEPTION
            'El rol % no puede ser participante de una asignación.', v_rol;
    END IF;

    SELECT codigo
      INTO v_estado
      FROM public.estados_participacion
     WHERE id = NEW.estado_participacion_id
       AND activo = true;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de participación no existe o está inactivo.';
    END IF;

    IF v_estado = 'PENDIENTE' THEN
        IF NEW.motivo_rechazo IS NOT NULL
           OR NEW.fecha_respuesta IS NOT NULL
           OR NEW.respondido_por IS NOT NULL THEN
            RAISE EXCEPTION
                'Una participación PENDIENTE no debe contener datos de respuesta.';
        END IF;

    ELSIF v_estado IN ('ACEPTADA', 'RECHAZADA')
          AND NEW.respondido_por IS DISTINCT FROM NEW.usuario_id THEN
        -- La aceptación/rechazo es una decisión personal del participante.
        -- WhatsApp actúa como canal técnico, pero el actor sigue siendo el
        -- usuario dueño de la participación.
        RAISE EXCEPTION
            'La participación solo puede ser aceptada o rechazada por el propio participante.';

    ELSIF v_estado = 'ACEPTADA' THEN
        IF NEW.fecha_respuesta IS NULL OR NEW.respondido_por IS NULL THEN
            RAISE EXCEPTION
                'Una participación ACEPTADA requiere fecha_respuesta y respondido_por.';
        END IF;

        IF NEW.motivo_rechazo IS NOT NULL THEN
            RAISE EXCEPTION
                'Una participación ACEPTADA no admite motivo_rechazo.';
        END IF;

    ELSIF v_estado = 'RECHAZADA' THEN
        IF NEW.fecha_respuesta IS NULL
           OR NEW.respondido_por IS NULL
           OR NEW.motivo_rechazo IS NULL
           OR btrim(NEW.motivo_rechazo) = '' THEN
            RAISE EXCEPTION
                'Una participación RECHAZADA requiere motivo, fecha_respuesta y respondido_por.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asignacion_participante() IS
'Impide asignar SUPERADMIN y valida los datos asociados al estado individual del participante.';

CREATE TRIGGER trg_validate_asignacion_participante
BEFORE INSERT OR UPDATE ON public.asignacion_participantes
FOR EACH ROW
EXECUTE FUNCTION public.validate_asignacion_participante();

-- ============================================================================
-- 11. PROFESORES / CONTACTOS DE COLEGIO
-- ============================================================================
CREATE TABLE public.contactos_colegio (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    colegio_id uuid NOT NULL,
    nombre varchar NOT NULL,
    email varchar NOT NULL,
    telefono varchar NOT NULL,
    cargo varchar NULL,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamptz NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NULL,
    updated_by uuid NULL,

    CONSTRAINT chk_contactos_colegio_nombre
        CHECK (btrim(nombre) <> ''),

    CONSTRAINT chk_contactos_colegio_email
        CHECK (btrim(email) <> ''),

    CONSTRAINT chk_contactos_colegio_telefono
        CHECK (btrim(telefono) <> ''),

    CONSTRAINT fk_contactos_colegio_colegio
        FOREIGN KEY (colegio_id)
        REFERENCES public.colegios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_contactos_colegio_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_contactos_colegio_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE public.contactos_colegio IS
'Profesores u otros contactos reutilizables asociados a un colegio.';

CREATE TABLE public.asignacion_contactos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asignacion_id uuid NOT NULL,
    contacto_colegio_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,

    CONSTRAINT uq_asignacion_contacto
        UNIQUE (asignacion_id, contacto_colegio_id),

    CONSTRAINT fk_asignacion_contactos_asignacion
        FOREIGN KEY (asignacion_id)
        REFERENCES public.asignaciones(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_asignacion_contactos_contacto
        FOREIGN KEY (contacto_colegio_id)
        REFERENCES public.contactos_colegio(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asignacion_contactos_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE public.asignacion_contactos IS
'Relaciona una actividad escolar con uno o dos profesores/contactos del mismo colegio.';

-- Valida que el contacto pertenezca al colegio de la asignación y limita a 2.
CREATE OR REPLACE FUNCTION public.validate_asignacion_contacto()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_asignacion_colegio uuid;
    v_contacto_colegio uuid;
    v_tipo varchar;
    v_count integer;
BEGIN
    SELECT a.colegio_id, ta.codigo
      INTO v_asignacion_colegio, v_tipo
      FROM public.asignaciones a
      JOIN public.tipos_actividad ta ON ta.id = a.tipo_actividad_id
     WHERE a.id = NEW.asignacion_id;

    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'La asignación indicada no existe.';
    END IF;

    IF v_tipo NOT IN ('ESPACIO_REFLEXION', 'ESPACIO_ENCUENTRO', 'REUNION') THEN
        RAISE EXCEPTION
            'El tipo de actividad % no admite profesores/contactos.', v_tipo;
    END IF;

    SELECT colegio_id
      INTO v_contacto_colegio
      FROM public.contactos_colegio
     WHERE id = NEW.contacto_colegio_id
       AND activo = true
       AND deleted_at IS NULL;

    IF v_contacto_colegio IS NULL THEN
        RAISE EXCEPTION 'El contacto no existe o no está activo.';
    END IF;

    IF v_contacto_colegio IS DISTINCT FROM v_asignacion_colegio THEN
        RAISE EXCEPTION
            'El contacto debe pertenecer al mismo colegio de la asignación.';
    END IF;

    SELECT count(*)
      INTO v_count
      FROM public.asignacion_contactos
     WHERE asignacion_id = NEW.asignacion_id
       AND id IS DISTINCT FROM NEW.id;

    IF v_count >= 2 THEN
        RAISE EXCEPTION
            'Una asignación escolar admite como máximo 2 profesores/contactos.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asignacion_contacto() IS
'Valida mismo colegio y máximo de dos contactos por actividad escolar.';

CREATE TRIGGER trg_validate_asignacion_contacto
BEFORE INSERT OR UPDATE ON public.asignacion_contactos
FOR EACH ROW
EXECUTE FUNCTION public.validate_asignacion_contacto();

-- REGLA DE CANTIDAD DE CONTACTOS
-- ----------------------------------------------------------------------------
-- El máximo de 2 se refuerza en validate_asignacion_contacto().
--
-- El mínimo de 1 contacto para ESPACIO_REFLEXION, ESPACIO_ENCUENTRO y REUNION
-- se valida en backend al crear/actualizar la actividad.
--
-- Motivo:
-- El backend actual utiliza Supabase/PostgREST en operaciones separadas.
-- Un constraint trigger diferido que obligara a tener un contacto al COMMIT
-- impediría crear primero la asignación y luego insertar sus contactos en otra
-- llamada. Cuando la creación completa se mueva a una RPC/transacción atómica,
-- esta regla podrá reforzarse también a nivel de base de datos.
--
-- Para CAPACITACION y EVENTO_CASA_CENTRAL, validate_asignacion_contacto()
-- impide insertar contactos.

-- ============================================================================
-- 12. ASISTENCIA INDIVIDUAL
-- ============================================================================
CREATE TABLE public.asistencias_asignacion (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asignacion_participante_id uuid NOT NULL UNIQUE,

    estado varchar NOT NULL DEFAULT 'PENDIENTE',
    motivo text NULL,
    motivo_regularizacion text NULL,

    informado_por uuid NULL,
    fecha_informe timestamptz NULL,

    latitud numeric NULL,
    longitud numeric NULL,
    precision_metros numeric NULL,
    direccion_detectada text NULL,
    fecha_geolocalizacion timestamptz NULL,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL,

    CONSTRAINT chk_asistencia_estado
        CHECK (estado IN ('PENDIENTE', 'PRESENTE', 'AUSENTE', 'JUSTIFICADA')),

    CONSTRAINT chk_asistencia_latitud
        CHECK (latitud IS NULL OR (latitud >= -90 AND latitud <= 90)),

    CONSTRAINT chk_asistencia_longitud
        CHECK (longitud IS NULL OR (longitud >= -180 AND longitud <= 180)),

    CONSTRAINT chk_asistencia_precision
        CHECK (precision_metros IS NULL OR precision_metros >= 0),

    CONSTRAINT fk_asistencias_participante
        FOREIGN KEY (asignacion_participante_id)
        REFERENCES public.asignacion_participantes(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_asistencias_informado_por
        FOREIGN KEY (informado_por)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_asistencias_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE public.asistencias_asignacion IS
'Asistencia individual. El participante requiere geolocalización; Directiva/SuperAdmin pueden regularizar con motivo.';

CREATE OR REPLACE FUNCTION public.validate_asistencia_asignacion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_participante_usuario uuid;
    v_informador_rol varchar;
BEGIN
    SELECT usuario_id
      INTO v_participante_usuario
      FROM public.asignacion_participantes
     WHERE id = NEW.asignacion_participante_id
       AND activo = true
       AND deleted_at IS NULL;

    IF v_participante_usuario IS NULL THEN
        RAISE EXCEPTION 'El participante no existe o no está activo.';
    END IF;

    IF NEW.estado = 'PENDIENTE' THEN
        IF NEW.informado_por IS NOT NULL
           OR NEW.fecha_informe IS NOT NULL
           OR NEW.latitud IS NOT NULL
           OR NEW.longitud IS NOT NULL
           OR NEW.fecha_geolocalizacion IS NOT NULL
           OR NEW.motivo_regularizacion IS NOT NULL THEN
            RAISE EXCEPTION
                'Una asistencia PENDIENTE no debe contener datos de marcación.';
        END IF;

        RETURN NEW;
    END IF;

    IF NEW.informado_por IS NULL OR NEW.fecha_informe IS NULL THEN
        RAISE EXCEPTION
            'Una asistencia informada requiere informado_por y fecha_informe.';
    END IF;

    IF NEW.estado IN ('AUSENTE', 'JUSTIFICADA')
       AND (NEW.motivo IS NULL OR btrim(NEW.motivo) = '') THEN
        RAISE EXCEPTION
            'AUSENTE y JUSTIFICADA requieren motivo.';
    END IF;

    IF NEW.informado_por = v_participante_usuario THEN
        -- Marcación propia: GPS obligatorio.
        IF NEW.latitud IS NULL
           OR NEW.longitud IS NULL
           OR NEW.fecha_geolocalizacion IS NULL THEN
            RAISE EXCEPTION
                'La marcación de asistencia propia requiere geolocalización.';
        END IF;

        -- No corresponde indicar regularización cuando el usuario marca lo suyo.
        IF NEW.motivo_regularizacion IS NOT NULL THEN
            RAISE EXCEPTION
                'Una marcación propia no admite motivo_regularizacion.';
        END IF;
    ELSE
        -- Regularización por tercero: solo Directiva o SuperAdmin.
        SELECT r.codigo
          INTO v_informador_rol
          FROM public.usuarios u
          JOIN public.roles r ON r.id = u.rol_id
         WHERE u.id = NEW.informado_por
           AND u.activo = true
           AND u.deleted_at IS NULL;

        IF v_informador_rol NOT IN ('DIRECTIVA', 'SUPERADMIN') THEN
            RAISE EXCEPTION
                'Solo DIRECTIVA o SUPERADMIN pueden regularizar asistencia de terceros.';
        END IF;

        IF NEW.motivo_regularizacion IS NULL
           OR btrim(NEW.motivo_regularizacion) = '' THEN
            RAISE EXCEPTION
                'La regularización administrativa requiere motivo_regularizacion.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_asistencia_asignacion() IS
'Valida estados, motivos, geolocalización obligatoria y regularización administrativa de asistencia.';

CREATE TRIGGER trg_validate_asistencia_asignacion
BEFORE INSERT OR UPDATE ON public.asistencias_asignacion
FOR EACH ROW
EXECUTE FUNCTION public.validate_asistencia_asignacion();

-- Cada participante recibe automáticamente un registro de asistencia PENDIENTE.
CREATE OR REPLACE FUNCTION public.create_pending_attendance_for_participant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.asistencias_asignacion (
        asignacion_participante_id,
        estado
    )
    VALUES (
        NEW.id,
        'PENDIENTE'
    );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.create_pending_attendance_for_participant() IS
'Crea automáticamente la asistencia PENDIENTE al incorporar un participante.';

CREATE TRIGGER trg_create_pending_attendance
AFTER INSERT ON public.asignacion_participantes
FOR EACH ROW
EXECUTE FUNCTION public.create_pending_attendance_for_participant();

-- ============================================================================
-- 13. HISTORIAL GLOBAL DE ASIGNACIÓN
-- ============================================================================
CREATE TABLE public.historial_asignacion (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asignacion_id uuid NOT NULL,
    accion varchar NOT NULL,
    estado_anterior_id uuid NULL,
    estado_nuevo_id uuid NULL,
    motivo text NULL,
    usuario_actor_id uuid NOT NULL,
    origen varchar NOT NULL DEFAULT 'WEB',
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_historial_asignacion
        FOREIGN KEY (asignacion_id)
        REFERENCES public.asignaciones(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_historial_estado_anterior
        FOREIGN KEY (estado_anterior_id)
        REFERENCES public.estados_asignacion(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_historial_estado_nuevo
        FOREIGN KEY (estado_nuevo_id)
        REFERENCES public.estados_asignacion(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_historial_usuario_actor
        FOREIGN KEY (usuario_actor_id)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE public.historial_asignacion IS
'Historial de eventos globales de la actividad. Los cambios individuales se trazan en asignacion_participantes y audit_logs.';

-- ============================================================================
-- 14. UPDATED_AT
-- ============================================================================
-- Reutiliza la función public.set_updated_at() existente en HuellAPP.
CREATE TRIGGER trg_tipos_actividad_updated_at
BEFORE UPDATE ON public.tipos_actividad
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_estados_asignacion_updated_at
BEFORE UPDATE ON public.estados_asignacion
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_espacios_encuentro_updated_at
BEFORE UPDATE ON public.espacios_encuentro
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_asignaciones_updated_at
BEFORE UPDATE ON public.asignaciones
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_tipos_participacion_updated_at
BEFORE UPDATE ON public.tipos_participacion
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_estados_participacion_updated_at
BEFORE UPDATE ON public.estados_participacion
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_asignacion_participantes_updated_at
BEFORE UPDATE ON public.asignacion_participantes
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_contactos_colegio_updated_at
BEFORE UPDATE ON public.contactos_colegio
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_asistencias_asignacion_updated_at
BEFORE UPDATE ON public.asistencias_asignacion
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- 15. ÍNDICES
-- ============================================================================
CREATE INDEX idx_asignaciones_tipo
    ON public.asignaciones(tipo_actividad_id);

CREATE INDEX idx_asignaciones_estado
    ON public.asignaciones(estado_id);

CREATE INDEX idx_asignaciones_fecha
    ON public.asignaciones(fecha);

CREATE INDEX idx_asignaciones_colegio
    ON public.asignaciones(colegio_id)
    WHERE colegio_id IS NOT NULL;

CREATE INDEX idx_espacios_encuentro_ramo
    ON public.espacios_encuentro(ramo_id);

CREATE INDEX idx_asignacion_participantes_asignacion
    ON public.asignacion_participantes(asignacion_id);

CREATE INDEX idx_asignacion_participantes_usuario
    ON public.asignacion_participantes(usuario_id);

CREATE INDEX idx_asignacion_participantes_estado
    ON public.asignacion_participantes(estado_participacion_id);

CREATE INDEX idx_contactos_colegio_colegio
    ON public.contactos_colegio(colegio_id);

CREATE INDEX idx_asignacion_contactos_asignacion
    ON public.asignacion_contactos(asignacion_id);

CREATE INDEX idx_asistencias_estado
    ON public.asistencias_asignacion(estado);

CREATE INDEX idx_historial_asignacion
    ON public.historial_asignacion(asignacion_id, created_at DESC);

-- ============================================================================
-- 16. PERMISOS
-- ============================================================================
-- Se conservan los permisos generales actuales:
-- VIEW_ASSIGNMENTS, CREATE_ASSIGNMENT, UPDATE_ASSIGNMENT,
-- REASSIGN_ASSIGNMENT y CANCEL_ASSIGNMENT.
--
-- ACCEPT_ASSIGNMENT y REJECT_ASSIGNMENT se reemplazan por permisos a nivel
-- de participación.

INSERT INTO public.permisos
    (codigo, nombre, descripcion, modulo, activo)
VALUES
    (
        'CREATE_TRAINING',
        'Crear capacitaciones',
        'Permite crear actividades de tipo CAPACITACION.',
        'ASIGNACIONES',
        true
    ),
    (
        'CREATE_CENTRAL_EVENT',
        'Crear eventos Casa Central',
        'Permite crear actividades de tipo EVENTO_CASA_CENTRAL.',
        'ASIGNACIONES',
        true
    ),
    (
        'ACCEPT_PARTICIPATION',
        'Aceptar participación',
        'Permite aceptar la participación propia en una asignación.',
        'ASIGNACIONES',
        true
    ),
    (
        'REJECT_PARTICIPATION',
        'Rechazar participación',
        'Permite rechazar la participación propia en una asignación.',
        'ASIGNACIONES',
        true
    ),
    (
        'REPORT_ATTENDANCE',
        'Registrar asistencia',
        'Permite registrar la asistencia propia con geolocalización.',
        'ASIGNACIONES',
        true
    ),
    (
        'MANAGE_ATTENDANCE',
        'Administrar asistencia',
        'Permite regularizar o corregir asistencia de terceros.',
        'ASIGNACIONES',
        true
    )
ON CONFLICT (codigo)
DO UPDATE SET
    nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    modulo = EXCLUDED.modulo,
    activo = true,
    updated_at = now();

-- SUPERADMIN: crea todos los tipos y puede administrar asistencia de terceros.
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permisos p
  ON p.codigo IN (
      'CREATE_TRAINING',
      'CREATE_CENTRAL_EVENT',
      'MANAGE_ATTENDANCE'
  )
WHERE r.codigo = 'SUPERADMIN'
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- DIRECTIVA: crea todos los tipos, responde si participa, registra su
-- asistencia y regulariza la de terceros.
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permisos p
  ON p.codigo IN (
      'CREATE_TRAINING',
      'CREATE_CENTRAL_EVENT',
      'ACCEPT_PARTICIPATION',
      'REJECT_PARTICIPATION',
      'REPORT_ATTENDANCE',
      'MANAGE_ATTENDANCE'
  )
WHERE r.codigo = 'DIRECTIVA'
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- COORDINADOR: no crea capacitación ni evento central.
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permisos p
  ON p.codigo IN (
      'ACCEPT_PARTICIPATION',
      'REJECT_PARTICIPATION',
      'REPORT_ATTENDANCE'
  )
WHERE r.codigo = 'COORDINADOR'
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- MONITOR: solo opera sobre sus propias participaciones.
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permisos p
  ON p.codigo IN (
      'ACCEPT_PARTICIPATION',
      'REJECT_PARTICIPATION',
      'REPORT_ATTENDANCE'
  )
WHERE r.codigo = 'MONITOR'
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

-- Retirar permisos antiguos que representaban aceptación/rechazo global.
DELETE FROM public.rol_permiso
WHERE permiso_id IN (
    SELECT id
    FROM public.permisos
    WHERE codigo IN ('ACCEPT_ASSIGNMENT', 'REJECT_ASSIGNMENT')
);

DELETE FROM public.permisos
WHERE codigo IN ('ACCEPT_ASSIGNMENT', 'REJECT_ASSIGNMENT');

-- ============================================================================
-- 17. RLS / ACCESO DIRECTO
-- ============================================================================
-- HuellAPP accede a estas tablas a través del backend usando service_role.
-- No se crean policies para anon/authenticated en esta migración.
ALTER TABLE public.tipos_actividad ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estados_asignacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.espacios_encuentro ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asignaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipos_participacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estados_participacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asignacion_participantes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contactos_colegio ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asignacion_contactos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_asignacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historial_asignacion ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.tipos_actividad FROM anon, authenticated;
REVOKE ALL ON public.estados_asignacion FROM anon, authenticated;
REVOKE ALL ON public.espacios_encuentro FROM anon, authenticated;
REVOKE ALL ON public.asignaciones FROM anon, authenticated;
REVOKE ALL ON public.tipos_participacion FROM anon, authenticated;
REVOKE ALL ON public.estados_participacion FROM anon, authenticated;
REVOKE ALL ON public.asignacion_participantes FROM anon, authenticated;
REVOKE ALL ON public.contactos_colegio FROM anon, authenticated;
REVOKE ALL ON public.asignacion_contactos FROM anon, authenticated;
REVOKE ALL ON public.asistencias_asignacion FROM anon, authenticated;
REVOKE ALL ON public.historial_asignacion FROM anon, authenticated;

GRANT ALL ON public.tipos_actividad TO service_role;
GRANT ALL ON public.estados_asignacion TO service_role;
GRANT ALL ON public.espacios_encuentro TO service_role;
GRANT ALL ON public.asignaciones TO service_role;
GRANT ALL ON public.tipos_participacion TO service_role;
GRANT ALL ON public.estados_participacion TO service_role;
GRANT ALL ON public.asignacion_participantes TO service_role;
GRANT ALL ON public.contactos_colegio TO service_role;
GRANT ALL ON public.asignacion_contactos TO service_role;
GRANT ALL ON public.asistencias_asignacion TO service_role;
GRANT ALL ON public.historial_asignacion TO service_role;

COMMIT;

-- ============================================================================
-- FIN MIGRACIÓN 010
--
-- VALIDACIONES QUE SIGUEN SIENDO RESPONSABILIDAD DEL BACKEND
-- ----------------------------------------------------------------------------
-- 1. Permisos de creación por rol:
--    SUPERADMIN  -> todos los tipos.
--    DIRECTIVA   -> todos los tipos.
--    COORDINADOR -> REFLEXION, ENCUENTRO, REUNION.
--    MONITOR     -> no crea.
--
-- 2. Scope:
--    MONITOR solo puede consultar/operar sus propias participaciones.
--
-- 3. Estado global:
--    Al aceptar el primer RELATOR, la asignación debe pasar de PENDIENTE a
--    CONFIRMADA y registrar historial/audit_logs.
--
-- 4. WhatsApp:
--    Validar de forma segura que la respuesta provenga del participante
--    asociado antes de aceptar/rechazar.
--
-- 5. Contactos escolares:
--    El backend debe exigir 1-2 contactos al crear/actualizar Reflexión,
--    Encuentro o Reunión. La BD refuerza mismo colegio y máximo 2.
--
-- 6. Auditoría:
--    Toda mutación relevante debe registrar audit_logs.
--
-- 7. Atomicidad:
--    Crear asignación + participantes + contactos + notificaciones debería
--    evolucionar a una operación transaccional/RPC para evitar estados
--    parciales si una llamada posterior falla.
-- ============================================================================
