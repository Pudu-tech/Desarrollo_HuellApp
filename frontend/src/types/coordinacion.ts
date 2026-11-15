/**
 * HuellApp · Contratos de coordinación por colegio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Tipar coordinadores asociados a colegios y sus monitores.
 * - Representar la advertencia de asignación excepcional multi-colegio.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Estos tipos solo describen respuestas del backend. FastAPI y las RPC
 * mantienen la autorización y validación definitiva.
 */

export interface ColegioReferenciaCoordinacion {
  id: string
  nombre: string
}

export interface CoordinadorColegioItem {
  relation_id: string
  coordinador_id: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string | null
  email: string
  activo: boolean
  otros_colegios: ColegioReferenciaCoordinacion[]
}

export interface MonitorCoordinadorItem {
  relation_id: string
  monitor_id: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string | null
  email: string
  activo: boolean
}

export interface MultiSchoolConflictDetail {
  code: 'MULTI_SCHOOL_CONFIRMATION_REQUIRED'
  message: string
  colegios: ColegioReferenciaCoordinacion[]
}

export interface UsuarioCoordinacionItem {
  id: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string | null
  email: string
}
