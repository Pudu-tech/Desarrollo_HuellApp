/** HuellApp · PATCH solo de campos editados; tipo y participantes quedan fijos. */
import type { AsignacionDetail, AsignacionPayload } from '../../types/asignaciones'
import type { AsignacionCambios } from '../../services/asignacionesService'

export function payloadEdicion(item: AsignacionDetail): AsignacionPayload {
  return { tipo_actividad_id: item.tipo_actividad_id, colegio_id: item.colegio_id, curso_colegio_id: item.curso_colegio_id,
    sala_id: item.sala_id, ramo_id: item.ramo_id, espacio_reflexion_id: item.espacio_reflexion_id,
    espacio_encuentro_id: item.espacio_encuentro_id, fecha: item.fecha, hora_inicio: item.hora_inicio, hora_fin: item.hora_fin,
    lugar: item.lugar, observacion: item.observacion,
    participantes: item.participantes.map(({ usuario_id, tipo_participacion_id }) => ({ usuario_id, tipo_participacion_id })),
    contactos: item.contactos.map(({ contacto_colegio_id }) => ({ contacto_colegio_id })) }
}
const normalizar = (key: string, value: unknown) => {
  if ((key === 'hora_inicio' || key === 'hora_fin') && typeof value === 'string') return value.length === 5 ? value + ':00' : value
  if (key === 'contactos') return (value as AsignacionPayload['contactos']).map((item) => item.contacto_colegio_id).sort().join(',')
  return value
}
export function cambiosEdicion(original: AsignacionPayload, nuevo: AsignacionPayload): AsignacionCambios {
  const changes: Record<string, unknown> = {}
  for (const key of Object.keys(original) as Array<keyof AsignacionPayload>) {
    if (key === 'participantes' || key === 'tipo_actividad_id') continue
    if (normalizar(key, original[key]) !== normalizar(key, nuevo[key])) changes[key] = nuevo[key]
  }
  if ('colegio_id' in changes) {
    changes.curso_colegio_id = nuevo.curso_colegio_id; changes.sala_id = nuevo.sala_id; changes.contactos = nuevo.contactos
  }
  return changes as AsignacionCambios
}
