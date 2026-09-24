/**
 * HuellAPP
 * Roles globales utilizados por el frontend.
 *
 * IMPORTANTE
 * ------------------------------------------------------------
 * Este archivo solo controla visibilidad y navegación.
 *
 * La autorización real continúa en FastAPI mediante permisos
 * y reglas de negocio del backend.
 */

export type RoleCode =
  | 'SUPERADMIN'
  | 'DIRECTIVA'
  | 'COORDINADOR'
  | 'MONITOR'

export const ADMIN_ROLES: RoleCode[] = [
  'SUPERADMIN',
  'DIRECTIVA',
]

export const ASSIGNMENT_MANAGEMENT_ROLES: RoleCode[] = [
  'SUPERADMIN',
  'DIRECTIVA',
  'COORDINADOR',
]

export const MONITOR_ROLES: RoleCode[] = [
  'MONITOR',
]

export function isRoleCode(
  value: string,
): value is RoleCode {
  return [
    'SUPERADMIN',
    'DIRECTIVA',
    'COORDINADOR',
    'MONITOR',
  ].includes(value)
}
