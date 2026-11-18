import type { AsignacionItem, CatalogosAsignacion } from '../types/asignaciones'
import { sortList, type SortState } from './listSort'
import type { ExportTable } from './queryExport'

export interface AssignmentFilters {
  search: string; tipoId: string; estadoId: string; colegioId: string
  desde: string; hasta: string; upcomingOnly: boolean
  coordinadorId?: string; monitorId?: string; cursoId?: string
}

const normalizeSearch = (text: string) => text.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLocaleLowerCase('es-CL').trim()
const matchesContext = (item: AsignacionItem, filters: AssignmentFilters) => (!filters.tipoId || item.tipo_actividad_id === filters.tipoId)
  && (!filters.colegioId || item.colegio_id === filters.colegioId)
  && (!filters.estadoId || filters.estadoId === 'POR_REASIGNAR' || item.estado_id === filters.estadoId)
  && (!filters.coordinadorId || (item.coordinadores ?? []).some(person => person.id === filters.coordinadorId))
  && (!filters.monitorId || (item.monitores ?? []).some(person => person.id === filters.monitorId))
  && (!filters.cursoId || item.curso_colegio_id === filters.cursoId)
  && (!filters.desde || item.fecha >= filters.desde) && (!filters.hasta || item.fecha <= filters.hasta)

export function mergeAssignmentCatalogs(previous: CatalogosAsignacion | null, fresh: CatalogosAsignacion): CatalogosAsignacion {
  const merge = <T extends { id: string }>(old: T[], next: T[]) => Array.from(new Map([...old, ...next].map(item => [item.id, item])).values())
  return { tipos_actividad: merge(previous?.tipos_actividad ?? [], fresh.tipos_actividad),
    estados: merge(previous?.estados ?? [], fresh.estados), colegios: merge(previous?.colegios ?? [], fresh.colegios) }
}

/** Actualiza el corte consultado conservando los registros fuera de ese contexto. */
export function mergeAssignmentSnapshot(previous: AsignacionItem[], fresh: AsignacionItem[], filters: AssignmentFilters): AsignacionItem[] {
  const ids = new Set(fresh.map(item => item.id))
  return [...previous.filter(item => !ids.has(item.id) && !matchesContext(item, filters)), ...fresh]
}

export function assignmentView(items: AsignacionItem[], catalogos: CatalogosAsignacion | null, filters: AssignmentFilters, sort: SortState) {
  const tipos = new Map(catalogos?.tipos_actividad.map(item => [item.id, item]) ?? [])
  const estados = new Map(catalogos?.estados.map(item => [item.id, item]) ?? [])
  const colegios = new Map(catalogos?.colegios.map(item => [item.id, item.nombre]) ?? [])
  const words = normalizeSearch(filters.search).split(/\s+/).filter(Boolean)
  const filtered = items.filter(item => {
    if (filters.upcomingOnly && ['REALIZADA', 'CANCELADA', 'NO_REALIZADA'].includes(estados.get(item.estado_id)?.codigo || '')) return false
    if (filters.estadoId === 'POR_REASIGNAR' ? !item.por_reasignar : filters.estadoId && (item.estado_id !== filters.estadoId || item.por_reasignar)) return false
    if (!matchesContext(item, filters)) return false
    const text = normalizeSearch([tipos.get(item.tipo_actividad_id)?.nombre, colegios.get(item.colegio_id ?? ''),
      item.lugar, item.observacion, item.curso_nombre,
      item.por_reasignar ? 'Por reasignar' : estados.get(item.estado_id)?.nombre,
      item.fecha, item.fecha.split('-').reverse().join('/'), item.hora_inicio.slice(0, 5), item.hora_fin.slice(0, 5),
      ...(item.monitores ?? []).map(person => person.nombre), ...(item.coordinadores ?? []).map(person => person.nombre),
      ...(item.asignados_a ?? [])].join(' '))
    return words.every(word => text.includes(word))
  })
  const values: Record<string, (row: AsignacionItem) => string | undefined | null> = {
    fecha: row => `${row.fecha} ${row.hora_inicio}`, actividad: row => tipos.get(row.tipo_actividad_id)?.nombre,
    colegio: row => colegios.get(row.colegio_id ?? '') ?? row.lugar, participantes: row => row.asignados_a?.join(', '),
    coordinadores: row => row.coordinadores?.map(person => person.nombre).join(', '),
    monitores: row => row.monitores?.map(person => person.nombre).join(', '),
  }
  return { filtered, ordered: sortList(filtered, values[sort.key], sort.direction), tipos, estados, colegios }
}

export const assignmentAttendanceText = (item: AsignacionItem) => Object.entries(item.asistencia_resumen ?? {})
  .filter(([, count]) => count > 0).map(([state, count]) => `${count} ${state === 'NO_REQUERIDA' ? 'no requerida' : state.toLowerCase()}`).join(' · ') || 'Sin registros'

export function assignmentsExportTable(items: AsignacionItem[], catalogos: CatalogosAsignacion, filters: AssignmentFilters, sort: SortState, generatedAt: string, showCoordinator = false): ExportTable {
  if (filters.desde && filters.hasta && filters.desde > filters.hasta) throw new Error('La fecha desde debe ser anterior o igual a la fecha hasta.')
  const view = assignmentView(items, catalogos, filters, sort)
  const coordinatorName = items.flatMap(item => item.coordinadores ?? []).find(person => person.id === filters.coordinadorId)?.nombre
  const monitorName = items.flatMap(item => item.monitores ?? []).find(person => person.id === filters.monitorId)?.nombre
  const courseName = items.find(item => item.curso_colegio_id === filters.cursoId)?.curso_nombre
  const criteria = [filters.search && `Buscar: ${filters.search}`, filters.tipoId && `Tipo: ${view.tipos.get(filters.tipoId)?.nombre ?? 'No disponible'}`,
    filters.estadoId && `Estado: ${filters.estadoId === 'POR_REASIGNAR' ? 'Por reasignar' : view.estados.get(filters.estadoId)?.nombre ?? 'No disponible'}`,
    filters.colegioId && `Colegio: ${view.colegios.get(filters.colegioId) ?? 'No disponible'}`, filters.desde && `Desde: ${filters.desde}`, filters.hasta && `Hasta: ${filters.hasta}`,
    filters.upcomingOnly && 'Solo próximas actividades'].filter(Boolean).join(' · ') || 'Sin filtros'
  const extraCriteria = [filters.coordinadorId && `Coordinador: ${coordinatorName ?? 'No disponible'}`,
    filters.monitorId && `Monitor: ${monitorName ?? 'No disponible'}`, filters.cursoId && `Curso: ${courseName ?? 'No disponible'}`].filter(Boolean)
  const labels: Record<string, string> = { fecha: 'Fecha', actividad: 'Actividad', colegio: 'Colegio / Lugar', participantes: 'Asignada a', coordinadores: 'Coordinador', monitores: 'Monitor' }
  return { title: 'Instancias', fileName: 'instancias', generatedAt, filters: [...(criteria === 'Sin filtros' ? [] : [criteria]), ...extraCriteria].join(' · ') || 'Sin filtros',
    order: `${labels[sort.key]} ${sort.direction === 'asc' ? 'ascendente' : 'descendente'}`,
    columns: ['Actividad', 'Colegio / Lugar', ...(showCoordinator ? ['Coordinador'] : []), 'Monitor', 'Fecha', 'Horario', 'Estado', 'Asistencia'],
    columnWidths: [28, 30, ...(showCoordinator ? [36] : []), 38, 16, 22, 20, 32],
    rows: view.ordered.map(item => [view.tipos.get(item.tipo_actividad_id)?.nombre ?? 'Actividad',
      item.colegio_id ? view.colegios.get(item.colegio_id) ?? 'Colegio no disponible' : item.lugar || '—',
      ...(showCoordinator ? [item.coordinadores?.length ? item.coordinadores.map(person => person.nombre).join('\n') : 'Sin coordinador asociado'] : []),
      item.monitores?.length ? item.monitores.map(person => person.nombre).join('\n') : 'Sin monitor', item.fecha.split('-').reverse().join('/'),
      `${item.hora_inicio.slice(0, 5)} – ${item.hora_fin.slice(0, 5)}`,
      item.por_reasignar ? 'Por reasignar' : view.estados.get(item.estado_id)?.nombre ?? 'Estado no disponible', assignmentAttendanceText(item)]),
  }
}
