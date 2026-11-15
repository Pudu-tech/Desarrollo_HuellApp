-- HuellAPP | Verificación estructural de 058.
-- Ejecutar después de aplicar 058. No persiste cambios.
BEGIN;
DO $$
DECLARE
    v_coord_role uuid;
    v_directiva_role uuid;
    v_superadmin_role uuid;
BEGIN
    ASSERT to_regclass('public.coordinador_monitor_colegio') IS NOT NULL,
        'Falta tabla coordinador_monitor_colegio';

    ASSERT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='usuario_colegio' AND column_name='updated_at'
    ), 'Falta usuario_colegio.updated_at';
    ASSERT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='usuario_colegio' AND column_name='updated_by'
    ), 'Falta usuario_colegio.updated_by';

    ASSERT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname='uq_coordinador_monitor_colegio'
          AND conrelid='public.coordinador_monitor_colegio'::regclass
    ), 'Falta unicidad coordinador-monitor-colegio';

    ASSERT EXISTS (
        SELECT 1 FROM public.permisos
        WHERE codigo='VIEW_SCHOOL_COORDINATORS' AND activo=true
    ), 'Falta VIEW_SCHOOL_COORDINATORS';
    ASSERT EXISTS (
        SELECT 1 FROM public.permisos
        WHERE codigo='MANAGE_SCHOOL_COORDINATORS' AND activo=true
    ), 'Falta MANAGE_SCHOOL_COORDINATORS';
    ASSERT EXISTS (
        SELECT 1 FROM public.permisos
        WHERE codigo='VIEW_COORDINATOR_MONITORS' AND activo=true
    ), 'Falta VIEW_COORDINATOR_MONITORS';
    ASSERT EXISTS (
        SELECT 1 FROM public.permisos
        WHERE codigo='MANAGE_COORDINATOR_MONITORS' AND activo=true
    ), 'Falta MANAGE_COORDINATOR_MONITORS';

    SELECT id INTO v_coord_role FROM public.roles WHERE codigo='COORDINADOR';
    SELECT id INTO v_directiva_role FROM public.roles WHERE codigo='DIRECTIVA';
    SELECT id INTO v_superadmin_role FROM public.roles WHERE codigo='SUPERADMIN';

    ASSERT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_coord_role AND p.codigo='VIEW_COORDINATOR_MONITORS'
    ), 'Coordinador debe poder consultar sus monitores';

    ASSERT NOT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_coord_role AND p.codigo='MANAGE_COORDINATOR_MONITORS'
    ), 'Coordinador no debe administrar relaciones';

    ASSERT NOT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_coord_role AND p.codigo='VIEW_SCHOOL_COORDINATORS'
    ), 'Coordinador no debe listar coordinadores de otros colegios';

    ASSERT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_directiva_role AND p.codigo='MANAGE_SCHOOL_COORDINATORS'
    ), 'Directiva debe administrar coordinadores';

    ASSERT EXISTS (
        SELECT 1 FROM public.rol_permiso rp JOIN public.permisos p ON p.id=rp.permiso_id
        WHERE rp.rol_id=v_superadmin_role AND p.codigo='MANAGE_COORDINATOR_MONITORS'
    ), 'Superadmin debe administrar relaciones';

    ASSERT NOT has_function_privilege(
        'anon',
        'public.gestionar_coordinador_colegio_atomico(text,uuid,uuid,boolean,uuid,uuid,inet,text)',
        'EXECUTE'
    ), 'anon no debe ejecutar gestión coordinador-colegio';
    ASSERT NOT has_function_privilege(
        'authenticated',
        'public.gestionar_coordinador_monitor_atomico(text,uuid,uuid,uuid,uuid,uuid,inet,text)',
        'EXECUTE'
    ), 'authenticated no debe ejecutar gestión coordinador-monitor';
    ASSERT has_function_privilege(
        'service_role',
        'public.gestionar_coordinador_colegio_atomico(text,uuid,uuid,boolean,uuid,uuid,inet,text)',
        'EXECUTE'
    ), 'service_role debe ejecutar gestión coordinador-colegio';

    RAISE NOTICE '058: estructura, permisos y privilegios aprobados';
END;
$$;
ROLLBACK;
