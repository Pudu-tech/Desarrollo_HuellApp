import type { AsignacionItem, CatalogosAsignacion } from '../types/asignaciones'
import { sortList, type SortState } from './listSort'
import type { ExportTable } from './queryExport'

export interface AssignmentFilters {
  search: string; tipoId: string; estadoId: string; colegioId: string
  desde: string; hasta: string; upcomingOnly: boolean
}

export function mergeAssignmentCatalogs(previous: CatalogosAsignacion | null, fresh: CatalogosAsignacion): CatalogosAsignacion {
  const merge = <T extends { id: string }>(old: T[], next: T[]) => Array.from(new Map([...old, ...next].map(item => [item.id, item])).values())
  return { tipos_actividad: merge(previous?.tipos_actividad ?? [], fresh.tipos_actividad),
    estados: merge(previous?.estados ?? [], fresh.estados), colegios: merge(previous?.colegios ?? [], fresh.colegios) }
}

/** Actualiza el corte consultado conservando los registros fuera de ese contexto. */
export function mergeAssignmentSnapshot(previous: AsignacionItem[], fresh: AsignacionItem[], filters: AssignmentFilters): AsignacionItem[] {
  const ids = new Set(fresh.map(item => item.id))
  const baseMatches = (item: AsignacionItem) => (!filters.tipoId || item.tipo_actividad_id === filters.tipoId)
    && (!filters.colegioId || item.colegio_id === filters.colegioId)
    && (!filters.estadoId || filters.estadoId === 'POR_REASIGNAR' || item.estado_id === filters.estadoId)
    && (!filters.desde || item.fecha >= filters.desde) && (!filters.hasta || item.fecha <= filters.hasta)
  return [...previous.filter(item => !ids.has(item.id) && !baseMatches(item)), ...fresh]
}

export function assignmentView(items: AsignacionItem[], catalogos: CatalogosAsignacion | null, filters: AssignmentFilters, sort: SortState) {
  const tipos = new Map(catalogos?.tipos_actividad.map(item => [item.id, item]) ?? [])
  const estados = new Map(catalogos?.estados.map(item => [item.id, item]) ?? [])
  const colegios = new Map(catalogos?.colegios.map(item => [item.id, item.nombre]) ?? [])
  const filtered = items.filter(item => {
    if (filters.upcomingOnly && ['REALIZADA', 'CANCELADA', 'NO_REALIZADA'].includes(estados.get(item.estado_id)?.codigo || '')) return false
    if (filters.tipoId && item.tipo_actividad_id !== filters.tipoId) return false
    if (filters.estadoId === 'POR_REASIGNAR' ? !item.por_reasignar : filters.estadoId && (item.estado_id !== filters.estadoId || item.por_reasignar)) return false
    if (filters.colegioId && item.colegio_id !== filters.colegioId) return false
    if (filters.desde && item.fecha < filters.desde) return false
    if (filters.hasta && item.fecha > filters.hasta) return false
    const text = `${tipos.get(item.tipo_actividad_id)?.nombre ?? ''} ${colegios.get(item.colegio_id ?? '') ?? ''} ${item.lugar ?? ''} ${item.observacion ?? ''}`
    return text.toLocaleLowerCase('es-CL').includes(filters.search.trim().toLocaleLowerCase('es-CL'))
  })
  const values: Record<string, (row: AsignacionItem) => string | undefined | null> = {
    fecha: row => `${row.fecha} ${row.hora_inicio}`, actividad: row => tipos.get(row.tipo_actividad_id)?.nombre,
    colegio: row => colegios.get(row.colegio_id ?? '') ?? row.lugar, participantes: row => row.asignados_a?.join(', '),
  }
  return { filtered, ordered: sortList(filtered, values[sort.key], sort.direction), tipos, estados, colegios }
}

export const assignmentAttendanceText = (item: AsignacionItem) => Object.entries(item.asistencia_resumen ?? {})
  .filter(([, count]) => count > 0).map(([state, count]) => `${count} ${state === 'NO_REQUERIDA' ? 'no requerida' : state.toLowerCase()}`).join(' · ') || 'Sin registros'

export function assignmentsExportTable(items: AsignacionItem[], catalogos: CatalogosAsignacion, filters: AssignmentFilters, sort: SortState, generatedAt: string): ExportTable {
  if (filters.desde && filters.hasta && filters.desde > filters.hasta) throw new Error('La fecha desde debe ser anterior o igual a la fecha hasta.')
  const view = assignmentView(items, catalogos, filters, sort)
  const criteria = [filters.search && `Buscar: ${filters.search}`, filters.tipoId && `Tipo: ${view.tipos.get(filters.tipoId)?.nombre ?? 'No disponible'}`,
    filters.estadoId && `Estado: ${filters.estadoId === 'POR_REASIGNAR' ? 'Por reasignar' : view.estados.get(filters.estadoId)?.nombre ?? 'No disponible'}`,
    filters.colegioId && `Colegio: ${view.colegios.get(filters.colegioId) ?? 'No disponible'}`, filters.desde && `Desde: ${filters.desde}`, filters.hasta && `Hasta: ${filters.hasta}`,
    filters.upcomingOnly && 'Solo próximas actividades'].filter(Boolean).join(' · ') || 'Sin filtros'
  const labels: Record<string, string> = { fecha: 'Fecha', actividad: 'Actividad', colegio: 'Colegio / Lugar', participantes: 'Asignada a' }
  return { title: 'Instancias', fileName: 'instancias', generatedAt, filters: criteria,
    order: `${labels[sort.key]} ${sort.direction === 'asc' ? 'ascendente' : 'descendente'}`,
    columns: ['Actividad', 'Colegio / Lugar', 'Asignada a', 'Fecha', 'Horario', 'Estado', 'Asistencia'],
    columnWidths: [28, 30, 38, 16, 22, 20, 32],
    rows: view.ordered.map(item => [view.tipos.get(item.tipo_actividad_id)?.nombre ?? 'Actividad',
      item.colegio_id ? view.colegios.get(item.colegio_id) ?? 'Colegio no disponible' : item.lugar || '—',
      item.asignados_a?.length ? item.asignados_a.join('\n') : 'Sin participantes', item.fecha.split('-').reverse().join('/'),
      `${item.hora_inicio.slice(0, 5)} – ${item.hora_fin.slice(0, 5)}`,
      item.por_reasignar ? 'Por reasignar' : view.estados.get(item.estado_id)?.nombre ?? 'Estado no disponible', assignmentAttendanceText(item)]),
  }
}
