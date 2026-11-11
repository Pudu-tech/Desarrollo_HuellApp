/**
 * HuellApp · Contratos de cursos y salas.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Definir las estructuras TypeScript utilizadas para cursos y salas.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Tipos compartidos entre servicios, componentes y páginas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Estos tipos no validan datos en ejecución ni conceden permisos.
 * La API es responsable de validar los datos y autorizar las operaciones.
 */
export interface CursoItem {
  id: string
  colegio_id: string
  nivel_curso_id: string
  seccion: string
  nombre_mostrado: string
  anio: number
  activo: boolean
  created_at: string
  updated_at: string
}

export interface CursoPayload {
  nivel_curso_id: string
  seccion: string
  anio: number
}

export interface NivelCursoItem {
  id: string
  codigo: string
  nombre: string
  orden: number
}

export interface SalaItem {
  id: string
  colegio_id: string
  nombre: string
  descripcion: string | null
  capacidad: number | null
  ubicacion: string | null
  activo: boolean
  created_at: string
  updated_at: string
}

export interface SalaPayload {
  nombre: string
  descripcion: string | null
  capacidad: number | null
  ubicacion: string | null
}
