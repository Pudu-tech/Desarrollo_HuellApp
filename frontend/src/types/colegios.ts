/**
 * Contrato del colegio que devuelve FastAPI.
 * Los campos opcionales se representan como null; el estado se modifica
 * exclusivamente mediante endpoints de activación/desactivación.
 */
export interface ColegioListItem {
  id: string
  rbd: string | null
  nombre: string
  descripcion: string | null
  tipo_dependencia_id: string | null
  direccion: string
  numero: string | null
  complemento: string | null
  comuna_id: string
  region_id: string
  codigo_postal: string | null
  telefono: string | null
  email: string | null
  sitio_web: string | null
  nombre_contacto: string | null
  telefono_contacto: string | null
  email_contacto: string | null
  activo: boolean
}

/**
 * Región disponible en el catálogo de ubicaciones.
 */
export interface RegionItem {
  id: string
  codigo: string
  nombre: string
}

/**
 * Comuna asociada a una región mediante region_id.
 */
export interface ComunaItem {
  id: string
  region_id: string
  nombre: string
}

/**
 * Tipo de administración educativa usado por colegios.
 */
export interface TipoDependenciaItem {
  id: string
  codigo: string
  nombre: string
  descripcion: string | null
}

/** Campos permitidos por POST /colegios; el backend define el estado y auditoría. */
export type ColegioCreatePayload = Omit<ColegioListItem, 'id' | 'activo'>
