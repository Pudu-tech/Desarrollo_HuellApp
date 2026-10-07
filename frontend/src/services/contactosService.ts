/**
 * HuellApp · Comunicación con el backend de contactos de colegios.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - La tabla contactos_colegio es la fuente compartida con Asignaciones.
 * - Las operaciones se autentican usando la sesión actual de Supabase.
 * - FastAPI valida permisos y audita las operaciones de escritura.
 * - DELETE devuelve 204: no se intenta interpretar una respuesta vacía.
 */
import { supabase } from './supabase'
import type { ContactoColegio, ContactoPayload } from '../types/contactos'

const configuredUrl = import.meta.env.VITE_API_URL
if (!configuredUrl) throw new Error('Falta la variable de entorno VITE_API_URL.')
const apiUrl = configuredUrl.replace(/\/+$/, '')

/** Ejecuta solicitudes autenticadas y transforma errores HTTP en mensajes visibles. */
async function contactRequest<T>(path: string, method = 'GET', payload?: object): Promise<T> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) throw new Error('Tu sesión no está disponible. Inicia sesión nuevamente.')
  const response = await fetch(`${apiUrl}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      Accept: 'application/json',
      ...(payload ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(payload ? { body: JSON.stringify(payload) } : {}),
  })
  if (!response.ok) {
    let message = 'No se pudo completar la operación de contactos.'
    try {
      const body = await response.json() as { detail?: string | Array<{ msg?: string }> }
      if (typeof body.detail === 'string') message = body.detail
      else if (Array.isArray(body.detail)) message = body.detail.map((item) => item.msg).filter(Boolean).join(' ') || message
    } catch { /* El servidor podría devolver una respuesta sin JSON. */ }
    if (response.status === 401) message = 'La sesión ha finalizado. Inicia sesión nuevamente.'
    if (response.status === 403) message = 'No tienes permisos para realizar esta operación.'
    throw new Error(message)
  }
  if (response.status === 204) return undefined as T
  return await response.json() as T
}

/** Obtiene contactos activos o también los inactivos, según los permisos. */
export const listContactos = (colegioId: string, incluirInactivos = false) =>
  contactRequest<ContactoColegio[]>(`/colegios/${encodeURIComponent(colegioId)}/contactos?incluir_inactivos=${incluirInactivos}`)

/** Crea un contacto, que podrá seleccionarse posteriormente en Asignaciones. */
export const createContacto = (colegioId: string, payload: ContactoPayload) =>
  contactRequest<ContactoColegio>(`/colegios/${encodeURIComponent(colegioId)}/contactos`, 'POST', payload)

/** Envía solo los campos cambiados y mantiene el identificador histórico. */
export const updateContacto = (colegioId: string, contactoId: string, changes: Partial<ContactoPayload>) =>
  contactRequest<ContactoColegio>(`/colegios/${encodeURIComponent(colegioId)}/contactos/${encodeURIComponent(contactoId)}`, 'PATCH', changes)

/** Ejecuta la transición reversible de estado auditada por FastAPI. */
export const setContactoActivo = (colegioId: string, contactoId: string, activo: boolean) =>
  contactRequest<ContactoColegio>(`/colegios/${encodeURIComponent(colegioId)}/contactos/${encodeURIComponent(contactoId)}/${activo ? 'activar' : 'desactivar'}`, 'POST')

/** Elimina lógicamente, conservando el historial y los vínculos con Asignaciones. */
export const deleteContacto = (colegioId: string, contactoId: string) =>
  contactRequest<void>(`/colegios/${encodeURIComponent(colegioId)}/contactos/${encodeURIComponent(contactoId)}`, 'DELETE')
