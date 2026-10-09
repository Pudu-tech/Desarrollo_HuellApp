/**
 * HuellApp · Cliente HTTP del listado, detalle y creación de Asignaciones.
 * Reutiliza el transporte autenticado; las escrituras son RPC auditadas en backend.
 * No envía actor, estado inicial ni campos de auditoría desde el navegador.
 */
import { recursoRequest } from './recursosService'
import type { AsignacionItem, AsignacionDetail, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion, OpcionesColegio, OpcionesEspacios } from '../types/asignaciones'

export const listAsignaciones = () => recursoRequest<AsignacionItem[]>('/asignaciones')
export const getAsignacionesResumen = (fresh = false) => recursoRequest<{ items: AsignacionItem[]; catalogos: CatalogosAsignacion; permissions: string[] }>('/asignaciones/resumen', 'GET', undefined, fresh)
export const getAsignacion = (id: string, fresh = false) => recursoRequest<AsignacionDetail>(`/asignaciones/${encodeURIComponent(id)}`, 'GET', undefined, fresh)
export const deleteAsignacion = (id: string) => recursoRequest<void>(`/asignaciones/${encodeURIComponent(id)}`, 'DELETE')
export const createAsignacion = (payload: AsignacionPayload) => recursoRequest<AsignacionDetail>('/asignaciones', 'POST', payload)
export type AsignacionCambios = Partial<Omit<AsignacionPayload, 'tipo_actividad_id' | 'participantes'>>
export const updateAsignacion = (id: string, cambios: AsignacionCambios) => recursoRequest<AsignacionDetail>(`/asignaciones/${encodeURIComponent(id)}`, 'PATCH', cambios)
export const getOpcionesEdicion = () => recursoRequest<OpcionesCreacion>('/catalogos/asignaciones/edicion')
export const getMonitoresReasignacion = () => recursoRequest<Array<{ id: string; nombres: string; apellido_paterno: string; apellido_materno: string | null }>>('/catalogos/asignaciones/reasignacion/participantes')
export const getOpcionesParticipantes = () => recursoRequest<{ participantes: Array<{ id: string; nombres: string; apellido_paterno: string; apellido_materno: string | null }>; tipos_participacion: Array<{ id: string; codigo: string; nombre: string }> }>('/catalogos/asignaciones/gestion-participantes')
export const addParticipante = (assignment: string, usuario: string, tipo: string) => recursoRequest(`/asignaciones/${encodeURIComponent(assignment)}/participantes`, 'POST', { usuario_id: usuario, tipo_participacion_id: tipo })
export const removeParticipante = (assignment: string, participant: string) => recursoRequest(`/asignaciones/${encodeURIComponent(assignment)}/participantes/${encodeURIComponent(participant)}`, 'DELETE')
export const reassignParticipante = (assignment: string, participant: string, usuario: string) => recursoRequest(`/asignaciones/${encodeURIComponent(assignment)}/participantes/${encodeURIComponent(participant)}/reasignar`, 'POST', { nuevo_usuario_id: usuario })
export const getColegioEdicion = (id: string) => recursoRequest<OpcionesColegio>(`/catalogos/asignaciones/edicion/colegios/${encodeURIComponent(id)}`)
export const getEspaciosEdicion = (id: string) => recursoRequest<OpcionesEspacios>(`/catalogos/asignaciones/edicion/ramos/${encodeURIComponent(id)}/espacios`)
export const getCatalogosAsignaciones = () => recursoRequest<CatalogosAsignacion>('/catalogos/asignaciones')
export const getOpcionesCreacion = () => recursoRequest<OpcionesCreacion>('/catalogos/asignaciones/creacion')
export const getOpcionesColegio = (id: string) => recursoRequest<OpcionesColegio>(`/catalogos/asignaciones/colegios/${encodeURIComponent(id)}`)
export const getOpcionesEspacios = (id: string) => recursoRequest<OpcionesEspacios>(`/catalogos/asignaciones/ramos/${encodeURIComponent(id)}/espacios`)
