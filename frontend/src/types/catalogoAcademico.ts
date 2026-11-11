/**
 * HuellApp · Contratos de catálogo académico.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Definir las estructuras TypeScript utilizadas para catálogo académico.
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
export type EntidadAcademica = 'asignaturas' | 'reflexion' | 'encuentro'
export interface RecursoAcademico {
  id: string
  nombre: string
  descripcion: string | null
  activo: boolean
  nivel_ids: string[]
  ramo_id: string | null
  orden: number | null
}
export interface NivelAcademico { id: string; nombre: string; activo: boolean }
export interface CatalogoAcademico {
  niveles: NivelAcademico[]
  asignaturas: RecursoAcademico[]
  reflexion: RecursoAcademico[]
  encuentro: RecursoAcademico[]
}
export type DatosAcademicos = {
  nombre: string; descripcion: string | null
} & ({ nivel_ids: string[] } | { ramo_id: string; orden: number | null })
