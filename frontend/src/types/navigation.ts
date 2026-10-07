/**
 * HuellApp
 * Tipos asociados a la navegación principal.
 *
 * Estos tipos representan únicamente permisos de visualización
 * en frontend. La autorización definitiva sigue perteneciendo
 * al backend.
 */

export type AppRole =
  | 'SUPERADMIN'
  | 'DIRECTIVA'
  | 'COORDINADOR'
  | 'MONITOR'

export interface NavigationItem {
  label: string
  path: string
  allowedRoles: AppRole[]
}