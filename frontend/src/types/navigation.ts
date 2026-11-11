/**
 * HuellApp · Contratos de navegación por rol.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Definir las estructuras TypeScript utilizadas para navegación por rol.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Tipos compartidos entre servicios, componentes y páginas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Estos tipos no validan datos en ejecución ni conceden permisos.
 * La API es responsable de validar los datos y autorizar las operaciones.
 *
 * NOTAS DE IMPLEMENTACIÓN
 * ------------------------------------------------------------
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