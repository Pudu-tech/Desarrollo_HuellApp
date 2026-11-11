/**
 * HuellApp · Utilidades de roles.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Centralizar la interpretación y presentación de los roles usados por la interfaz.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Ayuda compartida de navegación y visualización.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 *
 * NOTAS DE IMPLEMENTACIÓN
 * ------------------------------------------------------------
 * HuellApp
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

/** Comprueba si un texto corresponde a un rol conocido por la interfaz; no concede autorización. */
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
