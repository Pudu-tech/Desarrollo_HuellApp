/**
 * HuellApp · Cliente HTTP del listado, detalle y creación de Asignaciones.
 * Reutiliza el transporte autenticado; las escrituras son RPC auditadas en backend.
 * No envía actor, estado inicial ni campos de auditoría desde el navegador.
 */
import { recursoRequest } from './recursosService'
import type { AsignacionItem, AsignacionDetail, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion, OpcionesColegio, OpcionesEspacios } from '../types/asignaciones'

export const listAsignaciones = () => recursoRequest<AsignacionItem[]>('/asignaciones')
export const getAsignacion = (id: string) => recursoRequest<AsignacionDetail>(`/asignaciones/${encodeURIComponent(id)}`)
export const createAsignacion = (payload: AsignacionPayload) => recursoRequest<AsignacionDetail>('/asignaciones', 'POST', payload)
export type AsignacionCambios = Partial<Omit<AsignacionPayload, 'tipo_actividad_id' | 'participantes'>>
export const updateAsignacion = (id: string, cambios: AsignacionCambios) => recursoRequest<AsignacionDetail>(`/asignaciones/${encodeURIComponent(id)}`, 'PATCH', cambios)
export const getOpcionesEdicion = () => recursoRequest<OpcionesCreacion>('/catalogos/asignaciones/edicion')
export const getColegioEdicion = (id: string) => recursoRequest<OpcionesColegio>(`/catalogos/asignaciones/edicion/colegios/${encodeURIComponent(id)}`)
export const getEspaciosEdicion = (id: string) => recursoRequest<OpcionesEspacios>(`/catalogos/asignaciones/edicion/ramos/${encodeURIComponent(id)}/espacios`)
export const getCatalogosAsignaciones = () => recursoRequest<CatalogosAsignacion>('/catalogos/asignaciones')
export const getOpcionesCreacion = () => recursoRequest<OpcionesCreacion>('/catalogos/asignaciones/creacion')
export const getOpcionesColegio = (id: string) => recursoRequest<OpcionesColegio>(`/catalogos/asignaciones/colegios/${encodeURIComponent(id)}`)
export const getOpcionesEspacios = (id: string) => recursoRequest<OpcionesEspacios>(`/catalogos/asignaciones/ramos/${encodeURIComponent(id)}/espacios`)
