/**
 * HuellApp · Transporte común de Cursos, Salas y Asignaciones.
 * Reutiliza la sesión actual; FastAPI valida permisos y audita escrituras.
 * Maneja los errores Pydantic y las respuestas vacías de eliminación lógica.
 */
import { supabase } from './supabase'

/** Ejecuta una operación autenticada sin incorporar estado ni reglas de UI. */
export async function recursoRequest<T>(path: string, method = 'GET', payload?: object): Promise<T> {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) throw new Error('Tu sesión no está disponible. Inicia sesión nuevamente.')
  const apiUrl = import.meta.env.VITE_API_URL
  if (!apiUrl) throw new Error('Falta la variable de entorno VITE_API_URL.')
  const response = await fetch(`${apiUrl.replace(/\/+$/, '')}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      Accept: 'application/json',
      ...(payload ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(payload ? { body: JSON.stringify(payload) } : {}),
  })
  if (!response.ok) {
    const body = await response.json().catch(() => null) as {
      detail?: string | Array<{ msg?: string }>
    } | null
    const detail = body?.detail
    const message = typeof detail === 'string' ? detail
      : Array.isArray(detail) ? detail.map((item) => item.msg).filter(Boolean).join(' ') : ''
    throw new Error(message || 'No fue posible completar la operación.')
  }
  if (response.status === 204) return undefined as T
  return await response.json() as T
}

/** Consulta permisos efectivos una vez al abrir la ficha; no concede privilegios. */
export const getPermissions = () => recursoRequest<string[]>('/auth/permissions')
