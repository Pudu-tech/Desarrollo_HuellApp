/**
 * HuellAPP
 * Configuración centralizada de navegación.
 *
 * IMPORTANTE
 * ------------------------------------------------------------
 * Esta configuración determina qué enlaces son visibles
 * para cada rol.
 *
 * No reemplaza las validaciones realizadas por RoleRoute
 * ni la autorización implementada en FastAPI.
 */

import type {
  NavigationItem,
} from '../types/navigation'


// ============================================================
// NAVEGACIÓN ADMINISTRATIVA
// ============================================================

export const ADMIN_NAVIGATION_ITEMS:
  NavigationItem[] = [
    {
      label: 'Inicio',
      path: '/app/inicio',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
        'COORDINADOR',
      ],
    },
    {
      label: 'Usuarios',
      path: '/app/usuarios',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
      ],
    },
    {
      label: 'Colegios',
      path: '/app/colegios',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
      ],
    },
    {
      label: 'Cursos',
      path: '/app/cursos',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
      ],
    },
    {
      label: 'Salas',
      path: '/app/salas',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
      ],
    },
    {
      label: 'Asignaciones',
      path: '/app/asignaciones',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
        'COORDINADOR',
      ],
    },
    {
      label: 'Auditoría',
      path: '/app/auditoria',
      allowedRoles: [
        'SUPERADMIN',
      ],
    },
  ]


// ============================================================
// NAVEGACIÓN MONITOR
// ============================================================

export const MONITOR_NAVIGATION_ITEMS:
  NavigationItem[] = [
    {
      label: 'Inicio',
      path: '/app/monitor',
      allowedRoles: [
        'MONITOR',
      ],
    },
    {
      label: 'Mis asignaciones',
      path: '/app/monitor/asignaciones',
      allowedRoles: [
        'MONITOR',
      ],
    },
  ]