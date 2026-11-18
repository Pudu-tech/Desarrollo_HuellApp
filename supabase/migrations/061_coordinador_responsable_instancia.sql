/* ============================================================
   HuellAPP | Migración 061
   Coordinador responsable explícito por instancia.

   REGLAS
   ------------------------------------------------------------
   - Una instancia puede tener un único coordinador responsable.
   - Si un colegio tiene un único coordinador activo, se autoasigna.
   - Si tiene varios, la creación/edición debe indicar cuál es responsable.
   - Si crea un COORDINADOR, el responsable debe ser él mismo.
   - El coordinador seleccionado debe estar asignado activamente al colegio.
   - Históricos sin coordinador se conservan; solo se completa el dato cuando
     existe un único coordinador activo e inequívoco para el colegio.
   ============================================================ */
BEGIN;

ALTER TABLE public.asignaciones
    ADD COLUMN IF NOT EXISTS coordinador_id uuid;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_asignaciones_coordinador'
          AND conrelid = 'public.asignaciones'::regclass
    ) THEN
        ALTER TABLE public.asignaciones
            ADD CONSTRAINT fk_asignaciones_coordinador
            FOREIGN KEY (coordinador_id)
            REFERENCES public.usuarios(id)
            ON DELETE RESTRICT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_asignaciones_coordinador
    ON public.asignaciones(coordinador_id)
    WHERE deleted_at IS NULL;

/* Backfill conservador: solo cuando el colegio tiene exactamente un
   coordinador activo. No se inventa responsable en casos ambiguos. */
WITH unicos AS (
    SELECT uc.colegio_id, (array_agg(uc.usuario_id ORDER BY uc.usuario_id))[1] AS coordinador_id
    FROM public.usuario_colegio uc
    JOIN public.usuarios u ON u.id = uc.usuario_id
    JOIN public.roles r ON r.id = u.rol_id
    JOIN public.colegios c ON c.id = uc.colegio_id
    WHERE uc.activo = true
      AND u.activo = true
      AND u.deleted_at IS NULL
      AND r.codigo = 'COORDINADOR'
      AND c.deleted_at IS NULL
    GROUP BY uc.colegio_id
    HAVING count(*) = 1
)
UPDATE public.asignaciones a
SET coordinador_id = unicos.coordinador_id
FROM unicos
WHERE a.coordinador_id IS NULL
  AND a.colegio_id = unicos.colegio_id;

/* ------------------------------------------------------------
   Creación atómica: envolver la RPC existente para añadir responsable.
   ------------------------------------------------------------ */
ALTER FUNCTION public.crear_asignacion_atomica(
    uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,time,time,text,text,jsonb,jsonb,uuid,uuid,inet,text
) RENAME TO crear_asignacion_base_061;

REVOKE ALL ON FUNCTION public.crear_asignacion_base_061(
    uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,time,time,text,text,jsonb,jsonb,uuid,uuid,inet,text
) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.crear_asignacion_atomica(
    p_tipo_actividad_id uuid,
    p_colegio_id uuid,
    p_coordinador_id uuid,
    p_curso_colegio_id uuid,
    p_sala_id uuid,
    p_ramo_id uuid,
    p_espacio_reflexion_id uuid,
    p_espacio_encuentro_id uuid,
    p_fecha date,
    p_hora_inicio time,
    p_hora_fin time,
    p_lugar text,
    p_observacion text,
    p_participantes jsonb,
    p_contactos jsonb,
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
    v_result jsonb;
    v_asignacion_id uuid;
    v_coordinador_id uuid := p_coordinador_id;
    v_actor_role text;
    v_actor_role_id uuid;
    v_count integer;
    v_old jsonb;
    v_new jsonb;
BEGIN
    SELECT r.codigo, u.rol_id
    INTO v_actor_role, v_actor_role_id
    FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    IF v_actor_role IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;

    IF p_colegio_id IS NULL THEN
        v_coordinador_id := NULL;
    ELSE
        IF v_actor_role = 'COORDINADOR' THEN
            v_coordinador_id := p_actor_user_id;
        ELSIF v_coordinador_id IS NULL THEN
            SELECT count(*), (array_agg(uc.usuario_id ORDER BY uc.usuario_id))[1]
            INTO v_count, v_coordinador_id
            FROM public.usuario_colegio uc
            JOIN public.usuarios u ON u.id = uc.usuario_id
            JOIN public.roles r ON r.id = u.rol_id
            WHERE uc.colegio_id = p_colegio_id
              AND uc.activo = true
              AND u.activo = true
              AND u.deleted_at IS NULL
              AND r.codigo = 'COORDINADOR';

            IF v_count > 1 THEN
                RETURN jsonb_build_object('ok', false, 'error_code', 'COORDINATOR_REQUIRED');
            END IF;
        END IF;

        IF v_coordinador_id IS NOT NULL AND NOT EXISTS (
            SELECT 1
            FROM public.usuario_colegio uc
            JOIN public.usuarios u ON u.id = uc.usuario_id
            JOIN public.roles r ON r.id = u.rol_id
            WHERE uc.colegio_id = p_colegio_id
              AND uc.usuario_id = v_coordinador_id
              AND uc.activo = true
              AND u.activo = true
              AND u.deleted_at IS NULL
              AND r.codigo = 'COORDINADOR'
        ) THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_COORDINATOR');
        END IF;

        IF v_actor_role = 'COORDINADOR' AND v_coordinador_id IS DISTINCT FROM p_actor_user_id THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
        END IF;
    END IF;

    v_result := public.crear_asignacion_base_061(
        p_tipo_actividad_id,
        p_colegio_id,
        p_curso_colegio_id,
        p_sala_id,
        p_ramo_id,
        p_espacio_reflexion_id,
        p_espacio_encuentro_id,
        p_fecha,
        p_hora_inicio,
        p_hora_fin,
        p_lugar,
        p_observacion,
        p_participantes,
        p_contactos,
        p_actor_user_id,
        p_request_id,
        p_ip_address,
        p_user_agent
    );

    IF v_result->>'ok' <> 'true' THEN
        RETURN v_result;
    END IF;

    v_asignacion_id := (v_result->>'asignacion_id')::uuid;

    IF v_coordinador_id IS NOT NULL THEN
        SELECT to_jsonb(a) INTO v_old
        FROM public.asignaciones a
        WHERE a.id = v_asignacion_id;

        UPDATE public.asignaciones
        SET coordinador_id = v_coordinador_id,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_actor_user_id
        WHERE id = v_asignacion_id
        RETURNING to_jsonb(asignaciones) INTO v_new;

        INSERT INTO public.audit_logs(
            actor_user_id, actor_role_id, action, entity_type, entity_id,
            old_values, new_values, description, request_id,
            ip_address, user_agent, source
        ) VALUES (
            p_actor_user_id, v_actor_role_id,
            'ASSIGN_ASSIGNMENT_COORDINATOR', 'ASSIGNMENT', v_asignacion_id,
            v_old, v_new,
            'Coordinador responsable asociado a la instancia.',
            p_request_id, p_ip_address, p_user_agent, 'WEB'
        );
    END IF;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.crear_asignacion_atomica(
    uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,time,time,text,text,jsonb,jsonb,uuid,uuid,inet,text
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.crear_asignacion_atomica(
    uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,time,time,text,text,jsonb,jsonb,uuid,uuid,inet,text
) TO service_role;

/* ------------------------------------------------------------
   Edición atómica: envolver la RPC 048 y procesar coordinador_id.
   ------------------------------------------------------------ */
ALTER FUNCTION public.actualizar_asignacion_atomica(
    uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) RENAME TO actualizar_asignacion_base_061;

REVOKE ALL ON FUNCTION public.actualizar_asignacion_base_061(
    uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.actualizar_asignacion_atomica(
    p_asignacion_id uuid,
    p_cambios jsonb,
    p_reemplazar_contactos boolean,
    p_contactos jsonb,
    p_expected_updated_at timestamptz,
    p_campos_modificados text[],
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
    v_actual public.asignaciones%ROWTYPE;
    v_target_colegio uuid;
    v_target_coordinador uuid;
    v_actor_role text;
    v_actor_role_id uuid;
    v_count integer;
    v_result jsonb;
    v_old jsonb;
    v_new jsonb;
BEGIN
    SELECT * INTO v_actual
    FROM public.asignaciones
    WHERE id = p_asignacion_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'NOT_FOUND');
    END IF;

    SELECT r.codigo, u.rol_id
    INTO v_actor_role, v_actor_role_id
    FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE u.id = p_actor_user_id
      AND u.activo = true
      AND u.deleted_at IS NULL;

    v_target_colegio := CASE
        WHEN p_cambios ? 'colegio_id' THEN nullif(p_cambios->>'colegio_id', '')::uuid
        ELSE v_actual.colegio_id
    END;

    v_target_coordinador := CASE
        WHEN p_cambios ? 'coordinador_id' THEN nullif(p_cambios->>'coordinador_id', '')::uuid
        WHEN v_target_colegio IS NOT DISTINCT FROM v_actual.colegio_id THEN v_actual.coordinador_id
        ELSE NULL
    END;

    IF v_target_colegio IS NULL THEN
        v_target_coordinador := NULL;
    ELSIF v_actor_role = 'COORDINADOR' THEN
        v_target_coordinador := p_actor_user_id;
    ELSIF v_target_coordinador IS NULL THEN
        SELECT count(*), (array_agg(uc.usuario_id ORDER BY uc.usuario_id))[1]
        INTO v_count, v_target_coordinador
        FROM public.usuario_colegio uc
        JOIN public.usuarios u ON u.id = uc.usuario_id
        JOIN public.roles r ON r.id = u.rol_id
        WHERE uc.colegio_id = v_target_colegio
          AND uc.activo = true
          AND u.activo = true
          AND u.deleted_at IS NULL
          AND r.codigo = 'COORDINADOR';

        IF v_count > 1 THEN
            RETURN jsonb_build_object('ok', false, 'error_code', 'COORDINATOR_REQUIRED');
        END IF;
    END IF;

    IF v_target_coordinador IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.usuario_colegio uc
        JOIN public.usuarios u ON u.id = uc.usuario_id
        JOIN public.roles r ON r.id = u.rol_id
        WHERE uc.colegio_id = v_target_colegio
          AND uc.usuario_id = v_target_coordinador
          AND uc.activo = true
          AND u.activo = true
          AND u.deleted_at IS NULL
          AND r.codigo = 'COORDINADOR'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_COORDINATOR');
    END IF;

    IF v_actor_role = 'COORDINADOR' AND v_target_coordinador IS DISTINCT FROM p_actor_user_id THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    v_result := public.actualizar_asignacion_base_061(
        p_asignacion_id,
        p_cambios - 'coordinador_id',
        p_reemplazar_contactos,
        p_contactos,
        p_expected_updated_at,
        array_remove(p_campos_modificados, 'coordinador_id'),
        p_actor_user_id,
        p_request_id,
        p_ip_address,
        p_user_agent
    );

    IF v_result->>'ok' <> 'true' THEN
        RETURN v_result;
    END IF;

    IF v_target_coordinador IS DISTINCT FROM v_actual.coordinador_id THEN
        SELECT to_jsonb(a) INTO v_old FROM public.asignaciones a WHERE a.id = p_asignacion_id;
        UPDATE public.asignaciones
        SET coordinador_id = v_target_coordinador,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_actor_user_id
        WHERE id = p_asignacion_id
        RETURNING to_jsonb(asignaciones) INTO v_new;

        INSERT INTO public.audit_logs(
            actor_user_id, actor_role_id, action, entity_type, entity_id,
            old_values, new_values, description, request_id,
            ip_address, user_agent, source
        ) VALUES (
            p_actor_user_id, v_actor_role_id,
            'CHANGE_ASSIGNMENT_COORDINATOR', 'ASSIGNMENT', p_asignacion_id,
            v_old, v_new,
            'Coordinador responsable de la instancia actualizado.',
            p_request_id, p_ip_address, p_user_agent, 'WEB'
        );
    END IF;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_asignacion_atomica(
    uuid,jsonb,boolean,jsonb,timestamptz,text[],uuid,uuid,inet,text
) TO service_role;

COMMIT;
