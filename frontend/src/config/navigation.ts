/**
 * HuellApp
 * Configuración centralizada de navegación.
 *
 * IMPORTANTE
 * ------------------------------------------------------------
 * Esta configuración determina qué enlaces son visibles
 * para cada rol.
 * Cursos, Salas y Contactos se administran dentro de la ficha de Colegios.
 *
 * No reemplaza las validaciones realizadas por RoleRoute
 * ni la autorización implementada en FastAPI.
 */

import type {
  AppRole,
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
      label: 'Asignaciones',
      path: '/app/asignaciones',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
        'COORDINADOR',
      ],
    },
    {
      label: 'Catálogo académico',
      path: '/app/catalogo-academico',
      allowedRoles: ['SUPERADMIN', 'DIRECTIVA'],
    },
    {
      label: 'Mis asignaciones',
      path: '/app/mis-asignaciones',
      allowedRoles: ['DIRECTIVA', 'COORDINADOR'],
    },
    {
      label: 'Auditoría',
      path: '/app/auditoria',
      allowedRoles: [
        'SUPERADMIN',
        'DIRECTIVA',
      ],
    },
  ]

/** Orden de gestión común, conservando los accesos autorizados por rol. */
export function navigationForRole(role: AppRole): NavigationItem[] {
  const items = (role === 'MONITOR' ? MONITOR_NAVIGATION_ITEMS : ADMIN_NAVIGATION_ITEMS)
    .filter((item) => item.allowedRoles.includes(role))
  if (['SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'].includes(role)) {
    items.push({
      label: 'Asistencia', path: '/app/asistencia', allowedRoles: ['SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'],
    })
    const order = ['/app/inicio', '/app/usuarios', '/app/asignaciones', '/app/asistencia',
      '/app/mis-asignaciones', '/app/colegios', '/app/catalogo-academico', '/app/auditoria']
    items.sort((a, b) => order.indexOf(a.path) - order.indexOf(b.path))
  }
  return items
}


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
