/* ============================================================
   HuellAPP | Migración 043
   Administración de contactos de colegios con auditoría atómica.

   REGLAS
   ------------------------------------------------------------
   - No se reemplazan los contactos ni se modifican sus UUID.
   - Los contactos eliminados se conservan para el historial.
   - Solo se pueden gestionar contactos de colegios no eliminados.
   - No se desactivan ni eliminan contactos con asignaciones
     futuras vigentes: primero hay que reasignar responsables.
   - Las escrituras y auditorías comparten una transacción.
   - El límite de dos contactos por asignación sigue intacto.
   - Las RPC son exclusivas del backend (service_role).
   ============================================================ */
BEGIN;

/* Permisos independientes de los permisos del mantenedor de colegios. */
INSERT INTO public.permisos (codigo, nombre, descripcion, modulo, activo)
VALUES
 ('VIEW_SCHOOL_CONTACTS', 'Consultar contactos de colegios', 'Consulta contactos del establecimiento para gestión y asignaciones.', 'COLEGIOS', true),
 ('CREATE_SCHOOL_CONTACT', 'Crear contactos de colegios', 'Registra contactos del establecimiento.', 'COLEGIOS', true),
 ('UPDATE_SCHOOL_CONTACT', 'Editar contactos de colegios', 'Actualiza datos y permite activar o desactivar.', 'COLEGIOS', true),
 ('DELETE_SCHOOL_CONTACT', 'Eliminar contactos de colegios', 'Elimina lógicamente contactos sin asignaciones futuras vigentes.', 'COLEGIOS', true)
ON CONFLICT (codigo) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  descripcion = EXCLUDED.descripcion,
  modulo = EXCLUDED.modulo,
  activo = true;

/* El coordinador necesita consultar los contactos al asignar, pero no editarlos. */
INSERT INTO public.rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
FROM public.roles r CROSS JOIN public.permisos p
WHERE (p.codigo = 'VIEW_SCHOOL_CONTACTS' AND r.codigo IN ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'))
   OR (p.codigo IN ('CREATE_SCHOOL_CONTACT','UPDATE_SCHOOL_CONTACT') AND r.codigo IN ('SUPERADMIN','DIRECTIVA'))
   OR (p.codigo = 'DELETE_SCHOOL_CONTACT' AND r.codigo = 'SUPERADMIN')
ON CONFLICT (rol_id, permiso_id) DO NOTHING;

/* Garantiza que un mismo colegio no conserve dos RUT activos idénticos.
   No se impone en este paso: primero se deben revisar los históricos. */

CREATE OR REPLACE FUNCTION public.gestionar_contacto_colegio_atomico(
    p_accion text,
    p_colegio_id uuid,
    p_contacto_id uuid,
    p_datos jsonb,
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
    v_contacto record;
    v_id uuid;
    v_permiso text;
    v_old jsonb;
    v_new jsonb;
    v_nombre text;
    v_email text;
    v_telefono text;
    v_rut text;
BEGIN
    /* Validación en la BD: no confiar únicamente en FastAPI. */
    v_permiso := CASE p_accion
      WHEN 'CREATE' THEN 'CREATE_SCHOOL_CONTACT'
      WHEN 'UPDATE' THEN 'UPDATE_SCHOOL_CONTACT'
      WHEN 'ACTIVATE' THEN 'UPDATE_SCHOOL_CONTACT'
      WHEN 'DEACTIVATE' THEN 'UPDATE_SCHOOL_CONTACT'
      WHEN 'DELETE' THEN 'DELETE_SCHOOL_CONTACT'
      ELSE NULL END;
    IF v_permiso IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_ACTION');
    END IF;

    SELECT u.id, u.rol_id INTO v_actor
    FROM public.usuarios u
    WHERE u.id = p_actor_user_id AND u.activo = true AND u.deleted_at IS NULL;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'ACTOR_NOT_FOUND');
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.rol_permiso rp
      JOIN public.permisos pe ON pe.id = rp.permiso_id
      WHERE rp.rol_id = v_actor.rol_id AND pe.codigo = v_permiso AND pe.activo = true
    ) THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'FORBIDDEN');
    END IF;

    SELECT * INTO v_colegio FROM public.colegios
    WHERE id = p_colegio_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_NOT_FOUND');
    END IF;

    IF p_accion = 'CREATE' THEN
      IF v_colegio.activo IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_INACTIVE');
      END IF;
      IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object' THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
      END IF;
      v_nombre := NULLIF(btrim(p_datos->>'nombre'), '');
      v_email := NULLIF(btrim(p_datos->>'email'), '');
      v_telefono := NULLIF(btrim(p_datos->>'telefono'), '');
      IF v_nombre IS NULL OR v_email IS NULL OR v_telefono IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'REQUIRED_FIELDS');
      END IF;
      INSERT INTO public.contactos_colegio (
        colegio_id, nombre, apellido_paterno, apellido_materno, rut,
        email, telefono, cargo, created_by, updated_by
      ) VALUES (
        p_colegio_id, v_nombre,
        NULLIF(btrim(p_datos->>'apellido_paterno'), ''),
        NULLIF(btrim(p_datos->>'apellido_materno'), ''),
        NULLIF(btrim(p_datos->>'rut'), ''),
        v_email, v_telefono, NULLIF(btrim(p_datos->>'cargo'), ''),
        p_actor_user_id, p_actor_user_id
      ) RETURNING id INTO v_id;
      v_old := NULL;
    ELSE
      IF p_contacto_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'CONTACT_NOT_FOUND');
      END IF;
      SELECT * INTO v_contacto FROM public.contactos_colegio
      WHERE id = p_contacto_id AND colegio_id = p_colegio_id FOR UPDATE;
      IF NOT FOUND OR v_contacto.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'CONTACT_NOT_FOUND');
      END IF;
      v_id := v_contacto.id;
      v_old := to_jsonb(v_contacto);

      IF p_accion IN ('CREATE','UPDATE','ACTIVATE') AND v_colegio.activo IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'SCHOOL_INACTIVE');
      END IF;
      IF p_accion IN ('DEACTIVATE','DELETE') AND EXISTS (
        SELECT 1 FROM public.asignacion_contactos ac
        JOIN public.asignaciones a ON a.id = ac.asignacion_id
        WHERE ac.contacto_colegio_id = v_id
          AND a.activo = true AND a.deleted_at IS NULL AND a.fecha >= CURRENT_DATE
      ) THEN
        RETURN jsonb_build_object('ok', false, 'error_code', 'CONTACT_HAS_FUTURE_ASSIGNMENTS');
      END IF;

      IF p_accion = 'UPDATE' THEN
        IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object'
           OR p_datos ? 'id' OR p_datos ? 'colegio_id'
           OR p_datos ? 'activo' OR p_datos ? 'deleted_at' THEN
          RETURN jsonb_build_object('ok', false, 'error_code', 'INVALID_DATA');
        END IF;
        v_nombre := CASE WHEN p_datos ? 'nombre' THEN NULLIF(btrim(p_datos->>'nombre'), '') ELSE v_contacto.nombre END;
        v_email := CASE WHEN p_datos ? 'email' THEN NULLIF(btrim(p_datos->>'email'), '') ELSE v_contacto.email END;
        v_telefono := CASE WHEN p_datos ? 'telefono' THEN NULLIF(btrim(p_datos->>'telefono'), '') ELSE v_contacto.telefono END;
        IF v_nombre IS NULL OR v_email IS NULL OR v_telefono IS NULL THEN
          RETURN jsonb_build_object('ok', false, 'error_code', 'REQUIRED_FIELDS');
        END IF;
        UPDATE public.contactos_colegio SET
          nombre = v_nombre,
          apellido_paterno = CASE WHEN p_datos ? 'apellido_paterno' THEN NULLIF(btrim(p_datos->>'apellido_paterno'), '') ELSE apellido_paterno END,
          apellido_materno = CASE WHEN p_datos ? 'apellido_materno' THEN NULLIF(btrim(p_datos->>'apellido_materno'), '') ELSE apellido_materno END,
          rut = CASE WHEN p_datos ? 'rut' THEN NULLIF(btrim(p_datos->>'rut'), '') ELSE rut END,
          email = v_email, telefono = v_telefono,
          cargo = CASE WHEN p_datos ? 'cargo' THEN NULLIF(btrim(p_datos->>'cargo'), '') ELSE cargo END,
          updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      ELSIF p_accion = 'ACTIVATE' THEN
        UPDATE public.contactos_colegio
        SET activo = true, updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      ELSIF p_accion = 'DEACTIVATE' THEN
        UPDATE public.contactos_colegio
        SET activo = false, updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      ELSIF p_accion = 'DELETE' THEN
        UPDATE public.contactos_colegio
        SET activo = false, deleted_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP, updated_by = p_actor_user_id
        WHERE id = v_id;
      END IF;
    END IF;

    SELECT to_jsonb(c) INTO v_new FROM public.contactos_colegio c WHERE c.id = v_id;
    INSERT INTO public.audit_logs (
      actor_user_id, actor_role_id, action, entity_type, entity_id,
      old_values, new_values, description, request_id, ip_address, user_agent, source
    ) VALUES (
      p_actor_user_id, v_actor.rol_id, p_accion || '_SCHOOL_CONTACT',
      'SCHOOL_CONTACT', v_id, v_old, v_new,
      'Operación sobre contacto de colegio.', p_request_id, p_ip_address, p_user_agent, 'WEB'
    );
    RETURN jsonb_build_object('ok', true, 'contacto_id', v_id);
END;
$$;

COMMENT ON FUNCTION public.gestionar_contacto_colegio_atomico(
 text, uuid, uuid, jsonb, uuid, uuid, inet, text
) IS 'Administra contactos con RBAC y auditoría atómica; preserva las relaciones históricas.';

REVOKE ALL ON FUNCTION public.gestionar_contacto_colegio_atomico(
 text, uuid, uuid, jsonb, uuid, uuid, inet, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gestionar_contacto_colegio_atomico(
 text, uuid, uuid, jsonb, uuid, uuid, inet, text
) TO service_role;
COMMIT;
