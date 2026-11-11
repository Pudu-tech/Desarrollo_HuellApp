/**
 * HuellApp · Cliente HTTP de salas escolares.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Consultar salas y enviar cambios de datos, estado y eliminación lógica.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - El colegio se envía en la creación y no cambia desde la edición.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Utiliza la sesión del usuario; los permisos se validan en FastAPI.
 * Las credenciales privilegiadas de Supabase permanecen en el backend.
 */
import { recursoRequest } from './recursosService'
import type { SalaItem, SalaPayload } from '../types/recursos'

export const listSalas = (colegioId: string) =>
  recursoRequest<SalaItem[]>(`/salas?colegio_id=${encodeURIComponent(colegioId)}`)
export const createSala = (colegioId: string, payload: SalaPayload) =>
  recursoRequest<SalaItem>('/salas', 'POST', { ...payload, colegio_id: colegioId })
export const updateSala = (id: string, changes: Partial<SalaPayload>) =>
  recursoRequest<SalaItem>(`/salas/${encodeURIComponent(id)}`, 'PATCH', changes)
export const setSalaActivo = (id: string, activo: boolean) =>
  recursoRequest<SalaItem>(`/salas/${encodeURIComponent(id)}/${activo ? 'activate' : 'deactivate'}`, 'PATCH')
/** DELETE aplica eliminación lógica; la respuesta 204 no contiene JSON. */
export const deleteSala = (id: string) => recursoRequest<void>(`/salas/${encodeURIComponent(id)}`, 'DELETE')
