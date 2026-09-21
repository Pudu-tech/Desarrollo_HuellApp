-- ============================================================
-- HuellAPP
-- Migración 012
-- Gestión histórica y reasignación de participantes
-- ============================================================
--
-- OBJETIVO
-- ------------------------------------------------------------
-- Permitir que una participación sea archivada mediante soft-delete y que,
-- si posteriormente corresponde, el mismo usuario pueda volver a ser
-- incorporado a la misma asignación mediante un NUEVO registro histórico.
--
-- Antes de esta migración existía una restricción UNIQUE global sobre:
--
--     (asignacion_id, usuario_id)
--
-- Esa restricción impedía conservar la participación antigua y crear una
-- nueva participación para el mismo usuario, aunque la anterior estuviera
-- inactiva o tuviera deleted_at.
--
-- Nueva regla:
--
--     Un usuario puede tener como máximo UNA participación ACTIVA por
--     asignación, pero puede existir más de un registro histórico archivado.
--
-- También se ajusta el trigger de validación para que archivar una
-- participación siga siendo posible aunque el usuario haya sido desactivado
-- posteriormente.
--
-- Archivar historia no debe depender del estado actual del usuario.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. REEMPLAZAR UNIQUE GLOBAL POR UNIQUE PARCIAL
-- ============================================================

ALTER TABLE public.asignacion_participantes
DROP CONSTRAINT IF EXISTS uq_asignacion_participante_usuario;


DROP INDEX IF EXISTS
    public.uq_asignacion_participante_usuario_activo;


CREATE UNIQUE INDEX uq_asignacion_participante_usuario_activo
    ON public.asignacion_participantes (
        asignacion_id,
        usuario_id
    )
    WHERE activo = true
      AND deleted_at IS NULL;


COMMENT ON INDEX
public.uq_asignacion_participante_usuario_activo IS
'Garantiza una sola participación activa por usuario y asignación, permitiendo conservar participaciones históricas archivadas.';


COMMENT ON TABLE public.asignacion_participantes IS
'Usuarios que participan en una actividad. Un usuario puede tener múltiples registros históricos, pero solo una participación activa por asignación.';


-- ============================================================
-- 2. ÍNDICE PARA CONSULTAS DEL ROSTER ACTIVO
-- ============================================================

CREATE INDEX IF NOT EXISTS
    idx_asignacion_participantes_activos
ON public.asignacion_participantes (
    asignacion_id,
    usuario_id
)
WHERE activo = true
  AND deleted_at IS NULL;


-- ============================================================
-- 3. AJUSTAR VALIDACIÓN DE PARTICIPANTES
-- ============================================================
--
-- PROBLEMA ANTERIOR:
--
-- El trigger validaba que el usuario siguiera activo incluso al
-- ARCHIVAR una participación.
--
-- Ejemplo:
--
-- 1. Monitor es asignado.
-- 2. Posteriormente se desactiva su usuario.
-- 3. Administración intenta retirarlo/reasignarlo.
-- 4. El trigger podía impedir la operación porque el usuario ya
--    no estaba activo.
--
-- Eso no es correcto para trazabilidad histórica.
--
-- NUEVA REGLA:
--
-- Cuando una participación se archiva:
--
--     activo = false
--     deleted_at != null
--
-- se permite conservar el registro independientemente del estado
-- actual del usuario.
--
-- Para participaciones activas se mantienen todas las validaciones.
-- ============================================================


CREATE OR REPLACE FUNCTION
public.validate_asignacion_participante()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_rol varchar;
    v_usuario_activo boolean;
    v_usuario_deleted_at timestamptz;
    v_estado varchar;
BEGIN

    -- --------------------------------------------------------
    -- ARCHIVO HISTÓRICO
    -- --------------------------------------------------------
    --
    -- Archivar una participación no debe fallar porque el
    -- usuario haya sido desactivado después de ser asignado.
    --
    -- No alteramos aquí:
    -- - estado_participacion_id
    -- - motivo_rechazo
    -- - fecha_respuesta
    -- - respondido_por
    --
    -- Todos esos datos históricos permanecen intactos.
    -- --------------------------------------------------------

    IF NEW.activo IS FALSE
       AND NEW.deleted_at IS NOT NULL THEN

        RETURN NEW;

    END IF;


    -- --------------------------------------------------------
    -- VALIDAR USUARIO PARTICIPANTE ACTIVO
    -- --------------------------------------------------------

    SELECT
        r.codigo,
        u.activo,
        u.deleted_at
    INTO
        v_rol,
        v_usuario_activo,
        v_usuario_deleted_at
    FROM public.usuarios u
    JOIN public.roles r
        ON r.id = u.rol_id
    WHERE u.id = NEW.usuario_id;


    IF v_rol IS NULL THEN
        RAISE EXCEPTION
            'El usuario participante no existe.';
    END IF;


    IF v_usuario_activo IS NOT TRUE
       OR v_usuario_deleted_at IS NOT NULL THEN

        RAISE EXCEPTION
            'El usuario participante debe estar activo.';

    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ROL
    -- --------------------------------------------------------
    --
    -- SUPERADMIN administra el sistema, pero nunca participa.
    -- --------------------------------------------------------

    IF v_rol NOT IN (
        'DIRECTIVA',
        'COORDINADOR',
        'MONITOR'
    ) THEN

        RAISE EXCEPTION
            'El rol % no puede ser participante de una asignación.',
            v_rol;

    END IF;


    -- --------------------------------------------------------
    -- VALIDAR ESTADO DE PARTICIPACIÓN
    -- --------------------------------------------------------

    SELECT
        codigo
    INTO
        v_estado
    FROM public.estados_participacion
    WHERE id = NEW.estado_participacion_id
      AND activo = true;


    IF v_estado IS NULL THEN

        RAISE EXCEPTION
            'El estado de participación no existe o está inactivo.';

    END IF;


    -- --------------------------------------------------------
    -- PENDIENTE
    -- --------------------------------------------------------

    IF v_estado = 'PENDIENTE' THEN

        IF NEW.motivo_rechazo IS NOT NULL
           OR NEW.fecha_respuesta IS NOT NULL
           OR NEW.respondido_por IS NOT NULL THEN

            RAISE EXCEPTION
                'Una participación PENDIENTE no debe contener datos de respuesta.';

        END IF;


    -- --------------------------------------------------------
    -- ACEPTADA
    -- --------------------------------------------------------

    ELSIF v_estado = 'ACEPTADA' THEN

        IF NEW.fecha_respuesta IS NULL
           OR NEW.respondido_por IS NULL THEN

            RAISE EXCEPTION
                'Una participación ACEPTADA requiere fecha_respuesta y respondido_por.';

        END IF;


        IF NEW.motivo_rechazo IS NOT NULL THEN

            RAISE EXCEPTION
                'Una participación ACEPTADA no admite motivo_rechazo.';

        END IF;


    -- --------------------------------------------------------
    -- RECHAZADA
    -- --------------------------------------------------------

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


COMMENT ON FUNCTION
public.validate_asignacion_participante() IS
'Valida participantes activos y sus estados; permite archivar participaciones históricas aunque el usuario ya no esté activo.';


COMMIT;