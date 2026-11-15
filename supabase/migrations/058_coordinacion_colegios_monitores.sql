/* ============================================================
   HuellAPP | Migración 058
   Coordinadores por colegio y monitores por coordinador/colegio.

   REGLAS
   ------------------------------------------------------------
   - Un coordinador puede estar asociado a uno o más colegios.
   - La segunda asociación activa es excepcional y requiere confirmación.
   - Un monitor puede depender de más de un coordinador.
   - La relación coordinador-monitor siempre queda contextualizada
     por colegio para evitar ambigüedad entre establecimientos.
   - Todas las bajas son lógicas mediante activo=false.
   - Las escrituras se auditan dentro de la misma transacción.
   - Las RPC son exclusivas del backend (service_role).
   ============================================================ */
BEGIN;

/* ------------------------------------------------------------
   1. Completar trazabilidad de usuario_colegio existente.
   ------------------------------------------------------------ */
ALTER TABLE public.usuario_colegio
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_by uuid;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_usuario_colegio_updated_by'
          AND conrelid = 'public.usuario_colegio'::regclass
    ) THEN
        ALTER TABLE public.usuario_colegio
            ADD CONSTRAINT fk_usuario_colegio_updated_by
            FOREIGN KEY (updated_by)
            REFERENCES public.usuarios(id)
            ON DELETE SET NULL;
    END IF;
END $$;

/* ------------------------------------------------------------
   2. Relación coordinador-monitor contextualizada por colegio.
   ------------------------------------------------------------ */
CREATE TABLE IF NOT EXISTS public.coordinador_monitor_colegio (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    colegio_id uuid NOT NULL,
    coordinador_id uuid NOT NULL,
    monitor_id uuid NOT NULL,
    activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    CONSTRAINT uq_coordinador_monitor_colegio
        UNIQUE (colegio_id, coordinador_id, monitor_id),
    CONSTRAINT chk_coordinador_monitor_distintos
        CHECK (coordinador_id <> monitor_id),
    CONSTRAINT fk_cmc_colegio
        FOREIGN KEY (colegio_id)
        REFERENCES public.colegios(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_cmc_coordinador
        FOREIGN KEY (coordinador_id)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_cmc_monitor
        FOREIGN KEY (monitor_id)
        REFERENCES public.usuarios(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_cmc_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_cmc_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.usuarios(id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_cmc_colegio
    ON public.coordinador_monitor_colegio(colegio_id);
CREATE INDEX IF NOT EXISTS idx_cmc_coordinador
    ON public.coordinador_monitor_colegio(coordinador_id);
CREATE INDEX IF NOT EXISTS idx_cmc_monitor
    ON public.coordinador_monitor_colegio(monitor_id);
CREATE INDEX IF NOT EXISTS idx_cmc_activo
    ON public.coordinador_monitor_colegio(activo);

ALTER TABLE public.coordinador_monitor_colegio ENABLE ROW LEVEL SECURITY;

/* ------------------------------------------------------------
   3. Permisos de administración y consulta.
   ------------------------------------------------------------ */
INSERT INTO public.permisos (codigo, nombre, descripcion, modulo, activo)
VALUES
 ('VIEW_SCHOOL_COORDINATORS', 'Consultar coordinadores por colegio',
  'Consulta coordinadores asociados a un establecimiento.', 'COLEGIOS', true),
 ('MANAGE_SCHOOL_COORDINATORS', 'Gestionar coordinadores por colegio',
  'Asigna y desasigna coordinadores de establecimientos.', 'COLEGIOS', true),
 ('VIEW_COORDINATOR_MONITORS', 'Consultar monitores por coordinador',
  'Consulta los monitores asociados a un coordinador dentro de un colegio.', 'COLEGIOS', true),
 ('MANAGE_COORDINATOR_MONITORS', 'Gestionar monitores por coordinador',
  'Asigna y desasigna monitores de un coordinador dentro de un colegio.', 'COLEGIOS', true)
ON CONFLICT (codigo) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  descripcion = EXCLUDED.descripcion,
  modulo = EXCLUDED.modulo,
  activo = true;

INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permisos p
WHERE
    (p.codigo = 'VIEW_SCHOOL_COORDINATORS'
     AND r.codigo IN ('SUPERADMIN', 'DIRECTIVA'))
 OR (p.codigo = 'VIEW_COORDINATOR_MONITORS'
     AND r.codigo IN ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'))
 OR (p.codigo IN ('MANAGE_SCHOOL_COORDINATORS', 'MANAGE_COORDINATOR_MONITORS')
     AND r.codigo IN ('SUPERADMIN', 'DIRECTIVA'))
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

/* ------------------------------------------------------------
   4. Gestión atómica Coordinador <-> Colegio.
   ------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION public.gestionar_coordinador_colegio_atomico(
    p_accion text,
    p_colegio_id uuid,
    p_coordinador_id uuid,
    p_confirmar_multi_colegio boolean,
    p_actor_user_id uuid,
    p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor record;
    v_colegio record;
    v_coordinador record;
    v_relacion record;
    v_relacion_id uuid;
    v_old jsonb;
    v_new jsonb;
    v_otros_colegios jsonb := '[]'::jsonb;
    v_monitor_rel record;
BEGIN
    IF p_accion NOT IN ('ASSIGN', 'UNASSIGN') THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_ACTION');
    END IF;

    SELECT u.id, u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos pe ON pe.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND pe.codigo = 'MANAGE_SCHOOL_COORDINATORS'
          AND pe.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT c.id, c.nombre, c.activo, c.deleted_at
    INTO v_colegio
    FROM public.colegios c
    WHERE c.id = p_colegio_id
      AND c.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    SELECT u.id, u.nombres, u.apellido_paterno, u.apellido_materno,
           u.email, u.activo, u.deleted_at, r.codigo AS rol_codigo
    INTO v_coordinador
    FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE u.id = p_coordinador_id;

    IF NOT FOUND OR v_coordinador.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COORDINATOR_NOT_FOUND');
    END IF;

    IF v_coordinador.activo IS NOT TRUE OR v_coordinador.rol_codigo <> 'COORDINADOR' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_COORDINATOR');
    END IF;

    SELECT *
    INTO v_relacion
    FROM public.usuario_colegio uc
    WHERE uc.usuario_id = p_coordinador_id
      AND uc.colegio_id = p_colegio_id
    FOR UPDATE;

    IF p_accion = 'ASSIGN' THEN
        IF v_colegio.activo IS NOT TRUE THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_INACTIVE');
        END IF;

        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object('id', c.id, 'nombre', c.nombre)
                ORDER BY c.nombre
            ),
            '[]'::jsonb
        )
        INTO v_otros_colegios
        FROM public.usuario_colegio uc
        JOIN public.colegios c ON c.id = uc.colegio_id
        WHERE uc.usuario_id = p_coordinador_id
          AND uc.colegio_id <> p_colegio_id
          AND uc.activo = true
          AND c.activo = true
          AND c.deleted_at IS NULL;

        IF jsonb_array_length(v_otros_colegios) > 0
           AND COALESCE(p_confirmar_multi_colegio, false) IS NOT TRUE THEN
            RETURN jsonb_build_object(
                'ok', false,
                'error_code', 'MULTI_SCHOOL_CONFIRMATION_REQUIRED',
                'colegios', v_otros_colegios
            );
        END IF;

        IF v_relacion.id IS NULL THEN
            INSERT INTO public.usuario_colegio (
                usuario_id, colegio_id, activo,
                created_by, updated_by
            ) VALUES (
                p_coordinador_id, p_colegio_id, true,
                p_actor_user_id, p_actor_user_id
            )
            RETURNING id INTO v_relacion_id;
            v_old := NULL;
        ELSE
            v_relacion_id := v_relacion.id;
            v_old := to_jsonb(v_relacion);

            UPDATE public.usuario_colegio
            SET activo = true,
                updated_at = CURRENT_TIMESTAMP,
                updated_by = p_actor_user_id
            WHERE id = v_relacion_id;
        END IF;

        SELECT to_jsonb(uc)
        INTO v_new
        FROM public.usuario_colegio uc
        WHERE uc.id = v_relacion_id;

        INSERT INTO public.audit_logs (
            actor_user_id, actor_role_id, action, entity_type, entity_id,
            old_values, new_values, description, request_id,
            ip_address, user_agent, source
        ) VALUES (
            p_actor_user_id, v_actor.rol_id,
            'ASSIGN_SCHOOL_COORDINATOR', 'SCHOOL_COORDINATOR', v_relacion_id,
            v_old, v_new,
            'Coordinador asignado a colegio.', p_request_id,
            p_ip_address, p_user_agent, 'WEB'
        );

        RETURN jsonb_build_object(
            'ok', true,
            'relation_id', v_relacion_id,
            'colegios_previos', v_otros_colegios
        );
    END IF;

    /* UNASSIGN */
    IF v_relacion.id IS NULL OR v_relacion.activo IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'RELATION_NOT_FOUND');
    END IF;

    v_relacion_id := v_relacion.id;
    v_old := to_jsonb(v_relacion);

    /* Al quitar el coordinador del colegio, se desactivan también sus
       relaciones activas con monitores en ese mismo establecimiento. */
    FOR v_monitor_rel IN
        SELECT *
        FROM public.coordinador_monitor_colegio cmc
        WHERE cmc.colegio_id = p_colegio_id
          AND cmc.coordinador_id = p_coordinador_id
          AND cmc.activo = true
        FOR UPDATE
    LOOP
        UPDATE public.coordinador_monitor_colegio
        SET activo = false,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_actor_user_id
        WHERE id = v_monitor_rel.id;

        INSERT INTO public.audit_logs (
            actor_user_id, actor_role_id, action, entity_type, entity_id,
            old_values, new_values, description, request_id,
            ip_address, user_agent, source
        ) VALUES (
            p_actor_user_id, v_actor.rol_id,
            'UNASSIGN_COORDINATOR_MONITOR', 'COORDINATOR_MONITOR', v_monitor_rel.id,
            to_jsonb(v_monitor_rel),
            (SELECT to_jsonb(x) FROM public.coordinador_monitor_colegio x WHERE x.id = v_monitor_rel.id),
            'Monitor desasignado por baja del coordinador en el colegio.',
            p_request_id, p_ip_address, p_user_agent, 'WEB'
        );
    END LOOP;

    UPDATE public.usuario_colegio
    SET activo = false,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = v_relacion_id;

    SELECT to_jsonb(uc)
    INTO v_new
    FROM public.usuario_colegio uc
    WHERE uc.id = v_relacion_id;

    INSERT INTO public.audit_logs (
        actor_user_id, actor_role_id, action, entity_type, entity_id,
        old_values, new_values, description, request_id,
        ip_address, user_agent, source
    ) VALUES (
        p_actor_user_id, v_actor.rol_id,
        'UNASSIGN_SCHOOL_COORDINATOR', 'SCHOOL_COORDINATOR', v_relacion_id,
        v_old, v_new,
        'Coordinador desasignado de colegio.', p_request_id,
        p_ip_address, p_user_agent, 'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'relation_id', v_relacion_id);
END;
$$;

/* ------------------------------------------------------------
   5. Gestión atómica Coordinador <-> Monitor por colegio.
   ------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION public.gestionar_coordinador_monitor_atomico(
    p_accion text,
    p_colegio_id uuid,
    p_coordinador_id uuid,
    p_monitor_id uuid,
    p_actor_user_id uuid,
    p_request_id uuid DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor record;
    v_coordinador record;
    v_monitor record;
    v_relacion record;
    v_relacion_id uuid;
    v_old jsonb;
    v_new jsonb;
BEGIN
    IF p_accion NOT IN ('ASSIGN', 'UNASSIGN') THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_ACTION');
    END IF;

    SELECT u.id, u.rol_id
    INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.rol_permiso rp
        JOIN public.permisos pe ON pe.id = rp.permiso_id
        WHERE rp.rol_id = v_actor.rol_id
          AND pe.codigo = 'MANAGE_COORDINATOR_MONITORS'
          AND pe.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.colegios c
        WHERE c.id = p_colegio_id
          AND c.activo = true
          AND c.deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    SELECT u.id, u.activo, u.deleted_at, r.codigo AS rol_codigo
    INTO v_coordinador
    FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE u.id = p_coordinador_id;

    IF NOT FOUND OR v_coordinador.deleted_at IS NOT NULL
       OR v_coordinador.activo IS NOT TRUE
       OR v_coordinador.rol_codigo <> 'COORDINADOR' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_COORDINATOR');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.usuario_colegio uc
        WHERE uc.usuario_id = p_coordinador_id
          AND uc.colegio_id = p_colegio_id
          AND uc.activo = true
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'COORDINATOR_NOT_ASSIGNED_TO_SCHOOL');
    END IF;

    SELECT u.id, u.activo, u.deleted_at, r.codigo AS rol_codigo
    INTO v_monitor
    FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE u.id = p_monitor_id;

    IF NOT FOUND OR v_monitor.deleted_at IS NOT NULL
       OR v_monitor.activo IS NOT TRUE
       OR v_monitor.rol_codigo <> 'MONITOR' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_MONITOR');
    END IF;

    SELECT *
    INTO v_relacion
    FROM public.coordinador_monitor_colegio cmc
    WHERE cmc.colegio_id = p_colegio_id
      AND cmc.coordinador_id = p_coordinador_id
      AND cmc.monitor_id = p_monitor_id
    FOR UPDATE;

    IF p_accion = 'ASSIGN' THEN
        IF v_relacion.id IS NULL THEN
            INSERT INTO public.coordinador_monitor_colegio (
                colegio_id, coordinador_id, monitor_id, activo,
                created_by, updated_by
            ) VALUES (
                p_colegio_id, p_coordinador_id, p_monitor_id, true,
                p_actor_user_id, p_actor_user_id
            )
            RETURNING id INTO v_relacion_id;
            v_old := NULL;
        ELSE
            v_relacion_id := v_relacion.id;
            v_old := to_jsonb(v_relacion);
            UPDATE public.coordinador_monitor_colegio
            SET activo = true,
                updated_at = CURRENT_TIMESTAMP,
                updated_by = p_actor_user_id
            WHERE id = v_relacion_id;
        END IF;
    ELSE
        IF v_relacion.id IS NULL OR v_relacion.activo IS NOT TRUE THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'RELATION_NOT_FOUND');
        END IF;
        v_relacion_id := v_relacion.id;
        v_old := to_jsonb(v_relacion);
        UPDATE public.coordinador_monitor_colegio
        SET activo = false,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_actor_user_id
        WHERE id = v_relacion_id;
    END IF;

    SELECT to_jsonb(cmc)
    INTO v_new
    FROM public.coordinador_monitor_colegio cmc
    WHERE cmc.id = v_relacion_id;

    INSERT INTO public.audit_logs (
        actor_user_id, actor_role_id, action, entity_type, entity_id,
        old_values, new_values, description, request_id,
        ip_address, user_agent, source
    ) VALUES (
        p_actor_user_id, v_actor.rol_id,
        CASE WHEN p_accion = 'ASSIGN'
             THEN 'ASSIGN_COORDINATOR_MONITOR'
             ELSE 'UNASSIGN_COORDINATOR_MONITOR' END,
        'COORDINATOR_MONITOR', v_relacion_id,
        v_old, v_new,
        'Gestión de monitor bajo coordinador y colegio.',
        p_request_id, p_ip_address, p_user_agent, 'WEB'
    );

    RETURN jsonb_build_object('ok', true, 'relation_id', v_relacion_id);
END;
$$;

COMMENT ON FUNCTION public.gestionar_coordinador_colegio_atomico(
    text, uuid, uuid, boolean, uuid, uuid, inet, text
) IS 'Asigna/desasigna coordinadores por colegio con confirmación de multi-colegio y auditoría.';

COMMENT ON FUNCTION public.gestionar_coordinador_monitor_atomico(
    text, uuid, uuid, uuid, uuid, uuid, inet, text
) IS 'Asigna/desasigna monitores a coordinadores dentro de un colegio con auditoría.';

REVOKE ALL ON FUNCTION public.gestionar_coordinador_colegio_atomico(
    text, uuid, uuid, boolean, uuid, uuid, inet, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gestionar_coordinador_colegio_atomico(
    text, uuid, uuid, boolean, uuid, uuid, inet, text
) TO service_role;

REVOKE ALL ON FUNCTION public.gestionar_coordinador_monitor_atomico(
    text, uuid, uuid, uuid, uuid, uuid, inet, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gestionar_coordinador_monitor_atomico(
    text, uuid, uuid, uuid, uuid, uuid, inet, text
) TO service_role;

COMMIT;
