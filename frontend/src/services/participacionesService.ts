/** HuellApp · Una respuesta por participante, compartida entre correo y aplicación. */
import { recursoRequest } from './recursosService'

export interface ParticipacionPropia {
  asignacion_id: string; participante_id: string; invitacion_version: string
  estado: string; fecha_respuesta: string | null; motivo_rechazo: string | null
  actividad: string; fecha: string; hora_inicio: string; hora_fin: string
  colegio: string | null; curso: string | null; sala: string | null; asignatura: string | null
  lugar: string | null; observacion: string | null; admite_respuesta: boolean
  espacio: string | null; tipo_participacion: string | null
  recibida_at: string | null; actualizada_at: string | null; ultima_invitacion_at: string | null
}
export interface RespuestaParticipacion { accion: 'ACCEPT' | 'REJECT'; motivo: string | null }
export interface ResultadoRespuesta { estado: string; ya_respondida: boolean }
export const listMisParticipaciones = () => recursoRequest<ParticipacionPropia[]>('/mi-participacion')
export const getMiParticipacion = (id: string) => recursoRequest<ParticipacionPropia>(`/mi-participacion/${encodeURIComponent(id)}`)
export const responderMiParticipacion = (id: string, datos: RespuestaParticipacion) =>
  recursoRequest<ResultadoRespuesta>(`/mi-participacion/${encodeURIComponent(id)}/responder`, 'POST', datos)

/** El enlace es una credencial limitada. Nunca pasa por URL de API ni almacenamiento. */
async function invitacionRequest<T>(path: string, payload: object): Promise<T> {
  const api = import.meta.env.VITE_API_URL
  if (!api) throw new Error('Falta configurar la dirección de la API.')
  const response = await fetch(`${api.replace(/\/+$/, '')}/invitaciones/${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(payload), credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer',
  })
  const body = await response.json().catch(() => null)
  if (!response.ok) throw new Error(typeof body?.detail === 'string' ? body.detail : 'No fue posible consultar o responder esta invitación.')
  return body as T
}
export const consultarInvitacion = (token: string) => invitacionRequest<ParticipacionPropia>('consultar', { token })
export const responderInvitacion = (token: string, datos: RespuestaParticipacion) =>
  invitacionRequest<ResultadoRespuesta>('responder', { token, ...datos })
