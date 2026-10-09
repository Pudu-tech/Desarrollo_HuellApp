/** Transporte autenticado; todas las escrituras pasan por FastAPI y su RPC auditada. */
import { recursoRequest } from './recursosService'
import type { CatalogoAcademico, DatosAcademicos, EntidadAcademica, RecursoAcademico } from '../types/catalogoAcademico'

const root = '/catalogo-academico'
const resourcePath = (entidad: EntidadAcademica, id: string) => `${root}/${entidad}/${encodeURIComponent(id)}`
export const getCatalogoAcademico = () => recursoRequest<CatalogoAcademico>(root)
export const createRecursoAcademico = (entidad: EntidadAcademica, datos: DatosAcademicos) =>
  recursoRequest<RecursoAcademico>(`${root}/${entidad}`, 'POST', datos)
export const updateRecursoAcademico = (entidad: EntidadAcademica, id: string, datos: DatosAcademicos) =>
  recursoRequest<RecursoAcademico>(resourcePath(entidad, id), 'PUT', datos)
export const setRecursoAcademicoActivo = (entidad: EntidadAcademica, id: string, activo: boolean) =>
  recursoRequest<RecursoAcademico>(`${resourcePath(entidad, id)}/${activo ? 'activate' : 'deactivate'}`, 'PATCH')
export const deleteRecursoAcademico = (entidad: EntidadAcademica, id: string) =>
  recursoRequest<void>(resourcePath(entidad, id), 'DELETE')
