/**
 * HuellApp · Servicio de coordinación por colegio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Consultar coordinadores asociados a un colegio.
 * - Asignar/desasignar coordinadores.
 * - Administrar monitores de cada coordinador en el contexto del colegio.
 * - Preservar la advertencia estructurada cuando un coordinador ya pertenece
 *   a otro establecimiento.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Todas las operaciones usan la sesión actual. Los permisos y reglas de
 * negocio se validan nuevamente en FastAPI y las RPC de Supabase.
 */

import { supabase } from './supabase'
import type {
  CoordinadorColegioItem,
  MonitorCoordinadorItem,
  MultiSchoolConflictDetail,
  UsuarioCoordinacionItem,
} from '../types/coordinacion'

const rawApiUrl = import.meta.env.VITE_API_URL
if (!rawApiUrl) throw new Error('Falta la variable de entorno VITE_API_URL.')
const apiUrl = rawApiUrl.replace(/\/+$/, '')

export class MultiSchoolAssignmentError extends Error {
  readonly detail: MultiSchoolConflictDetail

  constructor(detail: MultiSchoolConflictDetail) {
    super(detail.message)
    this.name = 'MultiSchoolAssignmentError'
    this.detail = detail
  }
}

async function accessToken(): Promise<string> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) {
    throw new Error('La sesión ha finalizado. Inicia sesión nuevamente.')
  }
  return session.access_token
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = await accessToken()
  const send = () => fetch(`${apiUrl}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...options.headers,
    },
  })
  let response = await send()
  if (response.status === 503 && (options.method ?? 'GET') === 'GET') {
    await new Promise<void>((resolve) => setTimeout(resolve, 400))
    response = await send()
  }

  if (!response.ok) {
    let body: unknown = null
    try { body = await response.json() } catch { /* respuesta sin JSON */ }

    const detail = (body as { detail?: unknown } | null)?.detail
    if (
      response.status === 409
      && detail
      && typeof detail === 'object'
      && (detail as { code?: string }).code === 'MULTI_SCHOOL_CONFIRMATION_REQUIRED'
    ) {
      throw new MultiSchoolAssignmentError(detail as MultiSchoolConflictDetail)
    }

    if (typeof detail === 'string' && detail.trim()) throw new Error(detail)
    throw new Error('No fue posible completar la operación de coordinación.')
  }

  if (response.status === 204) return undefined as T
  return await response.json() as T
}


export const getCoordinatorCandidates = (colegioId: string) =>
  request<UsuarioCoordinacionItem[]>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores/candidatos`)

export const getMonitorCandidates = (colegioId: string, coordinadorId: string) =>
  request<UsuarioCoordinacionItem[]>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores/${encodeURIComponent(coordinadorId)}/monitores/candidatos`)

export const getSchoolCoordinators = (colegioId: string) =>
  request<CoordinadorColegioItem[]>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores`)

export const assignSchoolCoordinator = (
  colegioId: string,
  coordinadorId: string,
  confirmarMultiColegio = false,
) => request<CoordinadorColegioItem>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores`, {
  method: 'POST',
  body: JSON.stringify({
    coordinador_id: coordinadorId,
    confirmar_multi_colegio: confirmarMultiColegio,
  }),
})

export const unassignSchoolCoordinator = (colegioId: string, coordinadorId: string) =>
  request<void>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores/${encodeURIComponent(coordinadorId)}`, {
    method: 'DELETE',
  })

export const getCoordinatorMonitors = (colegioId: string, coordinadorId: string) =>
  request<MonitorCoordinadorItem[]>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores/${encodeURIComponent(coordinadorId)}/monitores`)

export const assignCoordinatorMonitor = (colegioId: string, coordinadorId: string, monitorId: string) =>
  request<MonitorCoordinadorItem>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores/${encodeURIComponent(coordinadorId)}/monitores`, {
    method: 'POST',
    body: JSON.stringify({ monitor_id: monitorId }),
  })

export const unassignCoordinatorMonitor = (colegioId: string, coordinadorId: string, monitorId: string) =>
  request<void>(`/colegios/${encodeURIComponent(colegioId)}/coordinadores/${encodeURIComponent(coordinadorId)}/monitores/${encodeURIComponent(monitorId)}`, {
    method: 'DELETE',
  })
