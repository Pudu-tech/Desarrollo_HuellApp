import { cachedFetch } from './readCache'
/**
 * HuellApp · Cliente HTTP de colegios y catálogos.
 *
 * SECURITY
 * ------------------------------------------------------------
 * - Cada solicitud obtiene el token de la sesión actual de Supabase.
 * - El token solo viaja en Authorization hacia FastAPI.
 * - Los permisos, validaciones y auditoría se aplican en backend.
 *
 * API ACTUAL
 * ------------------------------------------------------------
 * Consultas GET, creación POST, edición PATCH y cambio reversible de estado.
 * DELETE aplica eliminación lógica auditada mediante el backend.
 */

import { supabase } from './supabase'
import type {
  ColegioCreatePayload,
  ColegioListItem,
  ComunaItem,
  RegionItem,
  TipoDependenciaItem,
} from '../types/colegios'

const rawApiUrl = import.meta.env.VITE_API_URL
if (!rawApiUrl) {
  throw new Error('Falta la variable de entorno VITE_API_URL.')
}
const apiUrl = rawApiUrl.replace(/\/+$/, '')

interface ApiError {
  detail?: string | Array<{ msg?: string }>
}

/**
 * Realiza una consulta GET autenticada y traduce errores HTTP.
 * @param path Ruta relativa del backend.
 * @returns Respuesta JSON tipada según el contrato solicitado.
 */
async function requestJson<T>(path: string): Promise<T> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) {
    throw new Error('Tu sesión no está disponible. Inicia sesión nuevamente.')
  }

  const response = await cachedFetch(`${apiUrl}${path}`, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      Accept: 'application/json',
    },
  })

  if (!response.ok) {
    let message = 'No fue posible completar la solicitud.'
    try {
      const body = await response.json() as ApiError
      if (typeof body.detail === 'string') {
        message = body.detail
      } else if (Array.isArray(body.detail)) {
        message = body.detail.map((item) => item.msg).filter(Boolean).join(' ') || message
      }
    } catch {
      // La respuesta podría no ser JSON.
    }
    if (response.status === 401) message = 'La sesión ha finalizado. Inicia sesión nuevamente.'
    if (response.status === 403) message = 'No tienes permisos para consultar esta información.'
    throw new Error(message)
  }
  return await response.json() as T
}

/* ============================================================
   CONSULTAS DE COLEGIOS Y CATÁLOGOS
   ============================================================ */
export const getColegios = () => requestJson<ColegioListItem[]>('/colegios')
export const getRegiones = () => requestJson<RegionItem[]>('/catalogos/regiones')
export const getComunas = (regionId: string) =>
  requestJson<ComunaItem[]>(`/catalogos/comunas?region_id=${encodeURIComponent(regionId)}`)
export const getTiposDependencia = () =>
  requestJson<TipoDependenciaItem[]>('/catalogos/tipos-dependencia')

/**
 * Ejecuta una operación autenticada de escritura (POST o PATCH).
 * Las reglas de negocio y auditoría permanecen en el servidor.
 */
async function writeColegio(method: 'POST' | 'PATCH', path: string, body?: object): Promise<ColegioListItem> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) throw new Error('Tu sesión no está disponible. Inicia sesión nuevamente.')
  const response = await cachedFetch(`${apiUrl}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      Accept: 'application/json',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  })
  if (!response.ok) {
    let message = 'No fue posible completar la operación.'
    try {
      const data = await response.json() as ApiError
      if (typeof data.detail === 'string') message = data.detail
      else if (Array.isArray(data.detail)) message = data.detail.map((x) => x.msg).filter(Boolean).join(' ') || message
    } catch { /* Respuesta no JSON. */ }
    if (response.status === 401) message = 'La sesión ha finalizado. Inicia sesión nuevamente.'
    if (response.status === 403) message = 'No tienes permisos para realizar esta operación.'
    throw new Error(message)
  }
  return await response.json() as ColegioListItem
}

/* ============================================================
   OPERACIONES DE ESCRITURA
   ============================================================ */
/** Registra un colegio; el servidor asigna estado inicial y datos de auditoría. */
export const createColegio = (data: ColegioCreatePayload) => writeColegio('POST', '/colegios', data)
/** Edita exclusivamente los campos modificados. */
export const updateColegio = (id: string, changes: Partial<ColegioCreatePayload>) =>
  writeColegio('PATCH', `/colegios/${encodeURIComponent(id)}`, changes)
/** Cambia el estado por los endpoints existentes y auditados. */
export const activateColegio = (id: string) => writeColegio('PATCH', `/colegios/${encodeURIComponent(id)}/activate`)
export const deactivateColegio = (id: string) => writeColegio('PATCH', `/colegios/${encodeURIComponent(id)}/deactivate`)

/**
 * Elimina lógicamente un colegio mediante el endpoint auditado de FastAPI.
 *
 * SECURITY
 * ------------------------------------------------------------
 * El botón es exclusivo de SUPERADMIN en la interfaz; FastAPI valida
 * nuevamente DELETE_SCHOOL y protege las relaciones históricas.
 * Un DELETE exitoso devuelve 204 No Content (sin cuerpo JSON).
 *
 * @param id UUID del colegio, nunca su RBD.
 */
export async function deleteColegio(id: string): Promise<void> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) {
    throw new Error('Tu sesión no está disponible. Inicia sesión nuevamente.')
  }

  const response = await cachedFetch(`${apiUrl}/colegios/${encodeURIComponent(id)}`, {
    method: 'DELETE',
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      Accept: 'application/json',
    },
  })

  if (!response.ok) {
    let message = 'No fue posible eliminar el colegio.'
    try {
      const body = await response.json() as ApiError
      if (typeof body.detail === 'string') message = body.detail
      else if (Array.isArray(body.detail)) {
        message = body.detail.map((item) => item.msg).filter(Boolean).join(' ') || message
      }
    } catch {
      // Los errores HTTP no siempre incluyen un cuerpo JSON.
    }
    if (response.status === 401) message = 'La sesión ha finalizado. Inicia sesión nuevamente.'
    if (response.status === 403) message = 'No tienes permisos para eliminar colegios.'
    throw new Error(message)
  }
  // 204: no consumir response.json(), ya que no contiene cuerpo.
}
