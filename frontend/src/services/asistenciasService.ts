import { recursoRequest } from './recursosService'

export interface Asistencia {
  id: string; estado: string; motivo: string | null; motivo_regularizacion: string | null
  latitud: number | null; longitud: number | null; precision_gps: number | null
  direccion_detectada: string | null; comuna_detectada: string | null; region_detectada: string | null
  fecha_informe: string | null
}
export interface AsistenciaFila {
  id: string; asignacion_id: string; estado: { codigo: string }
  usuario: { nombres: string; apellido_paterno: string; apellido_materno: string | null }
  asistencia: Asistencia[] | Asistencia
  asignacion: { fecha: string; hora_inicio: string; hora_fin: string; lugar: string | null; actividad: { nombre: string }; colegio: { nombre: string } | null }
}
export const listAsistencias = () => recursoRequest<AsistenciaFila[]>('/asistencias', 'GET', undefined, true)
export const getAsistenciaPropia = (id: string) => recursoRequest<Asistencia>(`/asistencias/propia/${encodeURIComponent(id)}`, 'GET', undefined, true)
export const reportAsistencia = (assignment: string, participant: string, payload: object) => recursoRequest<Asistencia>(`/asignaciones/${assignment}/participaciones/${participant}/asistencia`, 'POST', payload)
export const regularizarAsistencia = (assignment: string, participant: string, payload: object) => recursoRequest<Asistencia>(`/asignaciones/${assignment}/participaciones/${participant}/asistencia/regularizar`, 'PATCH', payload)
