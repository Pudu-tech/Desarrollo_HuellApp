-- ============================================================
-- HuellAPP - Baseline de esquema Supabase
-- Reconstruido desde introspección del esquema remoto DEV/QA
-- Fecha de reconstrucción: 2026-09-13
--
-- IMPORTANTE:
-- - Este archivo representa el ESQUEMA actual de public.
-- - No pretende reproducir literalmente las migraciones históricas 001-006.
-- - No ejecutar sobre la base DEV/QA existente: está pensado para una base
--   Supabase nueva/vacía o como respaldo versionado del esquema actual.
-- - Los datos maestros existentes no se incluyen aquí.
-- ============================================================

BEGIN;

-- ============================================================
-- FUNCIONES
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
begin
    new.updated_at = now();
    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_audit_log_modification()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
begin
    raise exception 'Los registros de auditoría no pueden modificarse ni eliminarse.';
end;
$function$;

-- ============================================================
-- SEGURIDAD / RBAC
-- ============================================================

CREATE TABLE public.roles (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    descripcion text,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT roles_pkey PRIMARY KEY (id),
    CONSTRAINT roles_codigo_key UNIQUE (codigo)
);

CREATE TABLE public.permisos (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    descripcion text,
    modulo character varying,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT permisos_pkey PRIMARY KEY (id),
    CONSTRAINT permisos_codigo_key UNIQUE (codigo)
);

CREATE TABLE public.rol_permiso (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    rol_id uuid NOT NULL,
    permiso_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT rol_permiso_pkey PRIMARY KEY (id),
    CONSTRAINT uq_rol_permiso UNIQUE (rol_id, permiso_id),
    CONSTRAINT fk_rol_permiso_rol
        FOREIGN KEY (rol_id) REFERENCES public.roles(id) ON DELETE CASCADE,
    CONSTRAINT fk_rol_permiso_permiso
        FOREIGN KEY (permiso_id) REFERENCES public.permisos(id) ON DELETE CASCADE
);

-- ============================================================
-- CATÁLOGOS GEOGRÁFICOS / COLEGIOS
-- ============================================================

CREATE TABLE public.tipos_dependencia (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    descripcion text,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT tipos_dependencia_pkey PRIMARY KEY (id),
    CONSTRAINT tipos_dependencia_codigo_key UNIQUE (codigo)
);

CREATE TABLE public.regiones (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT regiones_pkey PRIMARY KEY (id),
    CONSTRAINT regiones_codigo_key UNIQUE (codigo),
    CONSTRAINT regiones_nombre_key UNIQUE (nombre)
);

CREATE TABLE public.comunas (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    region_id uuid NOT NULL,
    nombre character varying NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT comunas_pkey PRIMARY KEY (id),
    CONSTRAINT uq_comuna_region UNIQUE (region_id, nombre),
    CONSTRAINT fk_comunas_region
        FOREIGN KEY (region_id) REFERENCES public.regiones(id) ON DELETE RESTRICT
);

-- ============================================================
-- USUARIOS
-- ============================================================

CREATE TABLE public.usuarios (
    id uuid NOT NULL,
    rut character varying NOT NULL,
    nombres character varying NOT NULL,
    apellido_paterno character varying NOT NULL,
    apellido_materno character varying NOT NULL,
    fecha_nacimiento date,
    email character varying NOT NULL,
    telefono character varying,
    rol_id uuid NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    CONSTRAINT usuarios_pkey PRIMARY KEY (id),
    CONSTRAINT usuarios_email_key UNIQUE (email),
    CONSTRAINT usuarios_rut_key UNIQUE (rut),
    CONSTRAINT fk_usuarios_auth
        FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_usuarios_rol
        FOREIGN KEY (rol_id) REFERENCES public.roles(id) ON DELETE RESTRICT,
    CONSTRAINT fk_usuarios_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_usuarios_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

CREATE TABLE public.colegios (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    rbd character varying,
    nombre character varying NOT NULL,
    descripcion text,
    tipo_dependencia_id uuid,
    direccion character varying NOT NULL,
    numero character varying,
    complemento character varying,
    comuna_id uuid NOT NULL,
    region_id uuid NOT NULL,
    codigo_postal character varying,
    telefono character varying,
    email character varying,
    sitio_web character varying,
    nombre_contacto character varying,
    telefono_contacto character varying,
    email_contacto character varying,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    CONSTRAINT colegios_pkey PRIMARY KEY (id),
    CONSTRAINT colegios_rbd_key UNIQUE (rbd),
    CONSTRAINT fk_colegios_comuna
        FOREIGN KEY (comuna_id) REFERENCES public.comunas(id) ON DELETE RESTRICT,
    CONSTRAINT fk_colegios_region
        FOREIGN KEY (region_id) REFERENCES public.regiones(id) ON DELETE RESTRICT,
    CONSTRAINT fk_colegios_tipo_dependencia
        FOREIGN KEY (tipo_dependencia_id) REFERENCES public.tipos_dependencia(id) ON DELETE RESTRICT,
    CONSTRAINT fk_colegios_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_colegios_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

CREATE TABLE public.usuario_colegio (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    usuario_id uuid NOT NULL,
    colegio_id uuid NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    CONSTRAINT usuario_colegio_pkey PRIMARY KEY (id),
    CONSTRAINT uq_usuario_colegio UNIQUE (usuario_id, colegio_id),
    CONSTRAINT fk_usuario_colegio_usuario
        FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_usuario_colegio_colegio
        FOREIGN KEY (colegio_id) REFERENCES public.colegios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_usuario_colegio_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

-- ============================================================
-- MODELO ACADÉMICO
-- ============================================================

CREATE TABLE public.niveles_curso (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    orden integer NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT niveles_curso_pkey PRIMARY KEY (id),
    CONSTRAINT niveles_curso_codigo_key UNIQUE (codigo),
    CONSTRAINT niveles_curso_nombre_key UNIQUE (nombre),
    CONSTRAINT niveles_curso_orden_key UNIQUE (orden)
);

CREATE TABLE public.cursos_colegio (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    colegio_id uuid NOT NULL,
    nivel_curso_id uuid NOT NULL,
    seccion character varying NOT NULL,
    nombre_mostrado character varying NOT NULL,
    anio integer NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    CONSTRAINT cursos_colegio_pkey PRIMARY KEY (id),
    CONSTRAINT uq_curso_colegio_nivel_seccion_anio
        UNIQUE (colegio_id, nivel_curso_id, seccion, anio),
    CONSTRAINT fk_cursos_colegio_colegio
        FOREIGN KEY (colegio_id) REFERENCES public.colegios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_cursos_colegio_nivel
        FOREIGN KEY (nivel_curso_id) REFERENCES public.niveles_curso(id) ON DELETE RESTRICT,
    CONSTRAINT fk_cursos_colegio_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_cursos_colegio_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

CREATE TABLE public.ramos (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    nivel_curso_id uuid NOT NULL,
    codigo character varying,
    nombre character varying NOT NULL,
    descripcion text,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    CONSTRAINT ramos_pkey PRIMARY KEY (id),
    CONSTRAINT uq_ramo_nivel_nombre UNIQUE (nivel_curso_id, nombre),
    CONSTRAINT fk_ramos_nivel_curso
        FOREIGN KEY (nivel_curso_id) REFERENCES public.niveles_curso(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ramos_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_ramos_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

CREATE TABLE public.espacios_reflexion (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    nombre character varying NOT NULL,
    descripcion text,
    orden integer,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    ramo_id uuid NOT NULL,
    CONSTRAINT espacios_reflexion_pkey PRIMARY KEY (id),
    CONSTRAINT uq_espacio_reflexion_id_ramo UNIQUE (id, ramo_id),
    CONSTRAINT uq_espacio_reflexion_ramo_nombre UNIQUE (ramo_id, nombre),
    CONSTRAINT fk_espacios_reflexion_ramo
        FOREIGN KEY (ramo_id) REFERENCES public.ramos(id) ON DELETE RESTRICT,
    CONSTRAINT fk_espacios_reflexion_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_espacios_reflexion_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

CREATE TABLE public.salas (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    colegio_id uuid NOT NULL,
    nombre character varying NOT NULL,
    descripcion text,
    capacidad integer,
    ubicacion character varying,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    CONSTRAINT salas_pkey PRIMARY KEY (id),
    CONSTRAINT uq_sala_colegio_nombre UNIQUE (colegio_id, nombre),
    CONSTRAINT fk_salas_colegio
        FOREIGN KEY (colegio_id) REFERENCES public.colegios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_salas_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_salas_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

-- ============================================================
-- ASIGNACIONES
-- ============================================================

CREATE TABLE public.estados_asignacion (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    descripcion text,
    orden integer NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT estados_asignacion_pkey PRIMARY KEY (id),
    CONSTRAINT estados_asignacion_codigo_key UNIQUE (codigo)
);

CREATE TABLE public.asignaciones (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    colegio_id uuid NOT NULL,
    curso_colegio_id uuid NOT NULL,
    sala_id uuid NOT NULL,
    espacio_reflexion_id uuid NOT NULL,
    usuario_asignado_id uuid NOT NULL,
    fecha date NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL,
    estado_id uuid NOT NULL,
    motivo_rechazo text,
    fecha_respuesta timestamp with time zone,
    respondido_por uuid,
    observacion text,
    activo boolean NOT NULL DEFAULT true,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    updated_by uuid,
    ramo_id uuid NOT NULL,
    CONSTRAINT asignaciones_pkey PRIMARY KEY (id),
    CONSTRAINT chk_asignaciones_horas CHECK (hora_fin > hora_inicio),
    CONSTRAINT fk_asignaciones_colegio
        FOREIGN KEY (colegio_id) REFERENCES public.colegios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_curso
        FOREIGN KEY (curso_colegio_id) REFERENCES public.cursos_colegio(id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_espacio_ramo
        FOREIGN KEY (espacio_reflexion_id, ramo_id)
        REFERENCES public.espacios_reflexion(id, ramo_id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_estado
        FOREIGN KEY (estado_id) REFERENCES public.estados_asignacion(id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_ramo
        FOREIGN KEY (ramo_id) REFERENCES public.ramos(id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_respondido_por
        FOREIGN KEY (respondido_por) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_asignaciones_sala
        FOREIGN KEY (sala_id) REFERENCES public.salas(id) ON DELETE RESTRICT,
    CONSTRAINT fk_asignaciones_updated_by
        FOREIGN KEY (updated_by) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_asignaciones_usuario_asignado
        FOREIGN KEY (usuario_asignado_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT
);

CREATE TABLE public.historial_asignacion (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    asignacion_id uuid NOT NULL,
    accion character varying NOT NULL,
    estado_anterior_id uuid,
    estado_nuevo_id uuid,
    usuario_asignado_anterior_id uuid,
    usuario_asignado_nuevo_id uuid,
    motivo text,
    usuario_actor_id uuid NOT NULL,
    origen character varying NOT NULL DEFAULT 'WEB'::character varying,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT historial_asignacion_pkey PRIMARY KEY (id),
    CONSTRAINT fk_historial_asignacion
        FOREIGN KEY (asignacion_id) REFERENCES public.asignaciones(id) ON DELETE RESTRICT,
    CONSTRAINT fk_historial_estado_anterior
        FOREIGN KEY (estado_anterior_id) REFERENCES public.estados_asignacion(id) ON DELETE RESTRICT,
    CONSTRAINT fk_historial_estado_nuevo
        FOREIGN KEY (estado_nuevo_id) REFERENCES public.estados_asignacion(id) ON DELETE RESTRICT,
    CONSTRAINT fk_historial_usuario_actor
        FOREIGN KEY (usuario_actor_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_historial_usuario_anterior
        FOREIGN KEY (usuario_asignado_anterior_id) REFERENCES public.usuarios(id) ON DELETE SET NULL,
    CONSTRAINT fk_historial_usuario_nuevo
        FOREIGN KEY (usuario_asignado_nuevo_id) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

-- ============================================================
-- NOTIFICACIONES
-- ============================================================

CREATE TABLE public.notificaciones (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    usuario_destino_id uuid NOT NULL,
    tipo_notificacion character varying NOT NULL,
    titulo character varying NOT NULL,
    mensaje text NOT NULL,
    entidad_tipo character varying,
    entidad_id uuid,
    leida boolean NOT NULL DEFAULT false,
    fecha_lectura timestamp with time zone,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT notificaciones_pkey PRIMARY KEY (id),
    CONSTRAINT fk_notificaciones_usuario_destino
        FOREIGN KEY (usuario_destino_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT
);

CREATE TABLE public.notificacion_envios (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    notificacion_id uuid NOT NULL,
    canal character varying NOT NULL,
    estado character varying NOT NULL DEFAULT 'PENDIENTE'::character varying,
    proveedor character varying,
    identificador_externo character varying,
    fecha_intento timestamp with time zone,
    fecha_envio timestamp with time zone,
    error_mensaje text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT notificacion_envios_pkey PRIMARY KEY (id),
    CONSTRAINT chk_notificacion_envios_canal
        CHECK (canal::text = ANY (
            ARRAY[
                'INTERNA'::character varying,
                'WHATSAPP'::character varying,
                'EMAIL'::character varying
            ]::text[]
        )),
    CONSTRAINT chk_notificacion_envios_estado
        CHECK (estado::text = ANY (
            ARRAY[
                'PENDIENTE'::character varying,
                'ENVIADA'::character varying,
                'FALLIDA'::character varying
            ]::text[]
        )),
    CONSTRAINT fk_notificacion_envios_notificacion
        FOREIGN KEY (notificacion_id) REFERENCES public.notificaciones(id) ON DELETE CASCADE
);

-- ============================================================
-- AUDITORÍA
-- ============================================================

CREATE TABLE public.audit_logs (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    actor_user_id uuid,
    actor_role_id uuid,
    action character varying NOT NULL,
    entity_type character varying NOT NULL,
    entity_id uuid,
    old_values jsonb,
    new_values jsonb,
    description text,
    request_id uuid,
    ip_address inet,
    user_agent text,
    source character varying NOT NULL DEFAULT 'WEB'::character varying,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT audit_logs_pkey PRIMARY KEY (id),
    CONSTRAINT fk_audit_logs_actor_role
        FOREIGN KEY (actor_role_id) REFERENCES public.roles(id) ON DELETE SET NULL,
    CONSTRAINT fk_audit_logs_actor_user
        FOREIGN KEY (actor_user_id) REFERENCES public.usuarios(id) ON DELETE SET NULL
);

-- ============================================================
-- ÍNDICES NO GENERADOS AUTOMÁTICAMENTE POR PK/UNIQUE
-- ============================================================

CREATE INDEX idx_rol_permiso_permiso_id ON public.rol_permiso USING btree (permiso_id);
CREATE INDEX idx_rol_permiso_rol_id ON public.rol_permiso USING btree (rol_id);

CREATE INDEX idx_usuarios_activo ON public.usuarios USING btree (activo);
CREATE INDEX idx_usuarios_rol_id ON public.usuarios USING btree (rol_id);

CREATE INDEX idx_colegios_activo ON public.colegios USING btree (activo);
CREATE INDEX idx_colegios_comuna_id ON public.colegios USING btree (comuna_id);
CREATE INDEX idx_colegios_region_id ON public.colegios USING btree (region_id);

CREATE INDEX idx_usuario_colegio_colegio_id ON public.usuario_colegio USING btree (colegio_id);
CREATE INDEX idx_usuario_colegio_usuario_id ON public.usuario_colegio USING btree (usuario_id);

CREATE INDEX idx_cursos_colegio_anio ON public.cursos_colegio USING btree (anio);
CREATE INDEX idx_cursos_colegio_colegio_id ON public.cursos_colegio USING btree (colegio_id);
CREATE INDEX idx_cursos_colegio_nivel_curso_id ON public.cursos_colegio USING btree (nivel_curso_id);

CREATE INDEX idx_ramos_activo ON public.ramos USING btree (activo);
CREATE INDEX idx_ramos_nivel_curso_id ON public.ramos USING btree (nivel_curso_id);

CREATE INDEX idx_espacios_reflexion_ramo_id ON public.espacios_reflexion USING btree (ramo_id);

CREATE INDEX idx_salas_colegio_id ON public.salas USING btree (colegio_id);

CREATE INDEX idx_asignaciones_colegio_id ON public.asignaciones USING btree (colegio_id);
CREATE INDEX idx_asignaciones_curso_id ON public.asignaciones USING btree (curso_colegio_id);
CREATE INDEX idx_asignaciones_estado_id ON public.asignaciones USING btree (estado_id);
CREATE INDEX idx_asignaciones_fecha ON public.asignaciones USING btree (fecha);
CREATE INDEX idx_asignaciones_ramo_id ON public.asignaciones USING btree (ramo_id);
CREATE INDEX idx_asignaciones_sala_id ON public.asignaciones USING btree (sala_id);
CREATE INDEX idx_asignaciones_usuario_asignado_id ON public.asignaciones USING btree (usuario_asignado_id);

CREATE INDEX idx_historial_asignacion_id ON public.historial_asignacion USING btree (asignacion_id);
CREATE INDEX idx_historial_usuario_actor_id ON public.historial_asignacion USING btree (usuario_actor_id);

CREATE INDEX idx_notificaciones_created_at ON public.notificaciones USING btree (created_at);
CREATE INDEX idx_notificaciones_entidad ON public.notificaciones USING btree (entidad_tipo, entidad_id);
CREATE INDEX idx_notificaciones_leida ON public.notificaciones USING btree (leida);
CREATE INDEX idx_notificaciones_usuario_destino ON public.notificaciones USING btree (usuario_destino_id);

CREATE INDEX idx_notificacion_envios_canal ON public.notificacion_envios USING btree (canal);
CREATE INDEX idx_notificacion_envios_estado ON public.notificacion_envios USING btree (estado);
CREATE INDEX idx_notificacion_envios_notificacion_id ON public.notificacion_envios USING btree (notificacion_id);

CREATE INDEX idx_audit_logs_action ON public.audit_logs USING btree (action);
CREATE INDEX idx_audit_logs_actor_role_id ON public.audit_logs USING btree (actor_role_id);
CREATE INDEX idx_audit_logs_actor_user_id ON public.audit_logs USING btree (actor_user_id);
CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at);
CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity_type, entity_id);
CREATE INDEX idx_audit_logs_request_id ON public.audit_logs USING btree (request_id);

-- ============================================================
-- TRIGGERS updated_at
-- ============================================================

CREATE TRIGGER trg_asignaciones_updated_at
BEFORE UPDATE ON public.asignaciones
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_colegios_updated_at
BEFORE UPDATE ON public.colegios
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_comunas_updated_at
BEFORE UPDATE ON public.comunas
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_cursos_colegio_updated_at
BEFORE UPDATE ON public.cursos_colegio
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_espacios_reflexion_updated_at
BEFORE UPDATE ON public.espacios_reflexion
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_estados_asignacion_updated_at
BEFORE UPDATE ON public.estados_asignacion
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_niveles_curso_updated_at
BEFORE UPDATE ON public.niveles_curso
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_permisos_updated_at
BEFORE UPDATE ON public.permisos
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_ramos_updated_at
BEFORE UPDATE ON public.ramos
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_regiones_updated_at
BEFORE UPDATE ON public.regiones
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_roles_updated_at
BEFORE UPDATE ON public.roles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_salas_updated_at
BEFORE UPDATE ON public.salas
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_tipos_dependencia_updated_at
BEFORE UPDATE ON public.tipos_dependencia
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_usuarios_updated_at
BEFORE UPDATE ON public.usuarios
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- AUDIT LOGS APPEND-ONLY
-- ============================================================

CREATE TRIGGER trg_prevent_audit_logs_delete
BEFORE DELETE ON public.audit_logs
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_modification();

CREATE TRIGGER trg_prevent_audit_logs_update
BEFORE UPDATE ON public.audit_logs
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_modification();

-- ============================================================
-- ROW LEVEL SECURITY
-- Todas las tablas public tenían RLS habilitado y FORCE RLS false.
-- No existían policies en pg_policies.
-- ============================================================

ALTER TABLE public.asignaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colegios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comunas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cursos_colegio ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.espacios_reflexion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estados_asignacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historial_asignacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.niveles_curso ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notificacion_envios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permisos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ramos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regiones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rol_permiso ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipos_dependencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuario_colegio ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- GRANTS
-- Estado observado: postgres y service_role con privilegios de tabla;
-- anon/authenticated sin grants directos en las tablas public.
-- ============================================================

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;

COMMIT;
