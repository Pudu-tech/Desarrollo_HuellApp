/**
 * HuellApp · Reglas de presentación de creación, equivalentes a AsignacionCreate.
 * Las reglas definitivas, permisos y concurrencia permanecen en FastAPI/PostgreSQL.
 */
import type { AsignacionPayload } from '../../types/asignaciones'

export const TIPOS_ESCOLARES = new Set(['ESPACIO_REFLEXION', 'ESPACIO_ENCUENTRO', 'REUNION'])

/** Comprueba estructura, fechas/horas y combinaciones de contexto antes de POST. */
export function validarAsignacion(payload: AsignacionPayload, codigo: string): string | null {
  if (!payload.tipo_actividad_id || !payload.fecha || !payload.hora_inicio || !payload.hora_fin) return 'Indica tipo de actividad, fecha y horario.'
  if (payload.hora_fin <= payload.hora_inicio) return 'La hora de término debe ser posterior a la hora de inicio.'
  if (!payload.participantes.length || payload.participantes.some((item) => !item.usuario_id || !item.tipo_participacion_id)) return 'Selecciona al menos un participante y su tipo de participación.'
  if (new Set(payload.participantes.map((item) => item.usuario_id)).size !== payload.participantes.length) return 'No puedes repetir un participante.'
  if (payload.contactos.length > 2 || new Set(payload.contactos.map((item) => item.contacto_colegio_id)).size !== payload.contactos.length) return 'Selecciona como máximo dos contactos diferentes.'
  if (TIPOS_ESCOLARES.has(codigo)) {
    if (!payload.colegio_id || !payload.contactos.length) return 'Selecciona un colegio y al menos una persona de contacto.'
    if (payload.lugar) return 'Las actividades escolares no admiten un lugar independiente.'
    if (codigo === 'REUNION') {
      if (payload.ramo_id || payload.espacio_reflexion_id || payload.espacio_encuentro_id) return 'Reunión no admite ramo ni espacios académicos.'
    } else {
      if (!payload.curso_colegio_id || !payload.sala_id || !payload.ramo_id) return 'Selecciona curso, sala y ramo para esta actividad.'
      if (codigo === 'ESPACIO_REFLEXION' && (!payload.espacio_reflexion_id || payload.espacio_encuentro_id)) return 'Selecciona un espacio de reflexión del ramo.'
      if (codigo === 'ESPACIO_ENCUENTRO' && (!payload.espacio_encuentro_id || payload.espacio_reflexion_id)) return 'Selecciona un espacio de encuentro del ramo.'
    }
  } else if (codigo === 'CAPACITACION' || codigo === 'EVENTO_CASA_CENTRAL') {
    if (!payload.lugar?.trim()) return 'Indica el lugar de la actividad.'
    if (payload.colegio_id || payload.curso_colegio_id || payload.sala_id || payload.ramo_id || payload.espacio_reflexion_id || payload.espacio_encuentro_id || payload.contactos.length) return 'Esta actividad no admite contexto escolar ni contactos del colegio.'
  } else return 'El tipo de actividad no está disponible en este formulario.'
  return null
}
