/**
 * HuellApp · Operaciones de Cursos dentro de un colegio.
 * Reutiliza /cursos y sus RPC auditadas. PATCH nunca cambia la pertenencia.
 */
import { recursoRequest } from './recursosService'
import type { CursoItem, CursoPayload, NivelCursoItem } from '../types/recursos'

/** Filtra en backend para que la ficha reciba exclusivamente sus cursos. */
export const listCursos = (colegioId: string) =>
  recursoRequest<CursoItem[]>(`/cursos?colegio_id=${encodeURIComponent(colegioId)}`)
export const getNivelesCurso = () => recursoRequest<NivelCursoItem[]>('/catalogos/niveles-curso')
export const createCurso = (colegioId: string, payload: CursoPayload) =>
  recursoRequest<CursoItem>('/cursos', 'POST', { ...payload, colegio_id: colegioId })
export const updateCurso = (id: string, changes: Partial<CursoPayload>) =>
  recursoRequest<CursoItem>(`/cursos/${encodeURIComponent(id)}`, 'PATCH', changes)
export const setCursoActivo = (id: string, activo: boolean) =>
  recursoRequest<CursoItem>(`/cursos/${encodeURIComponent(id)}/${activo ? 'activate' : 'deactivate'}`, 'PATCH')
/** El historial se conserva; el servidor bloquea las asignaciones futuras vigentes. */
export const deleteCurso = (id: string) => recursoRequest<void>(`/cursos/${encodeURIComponent(id)}`, 'DELETE')
