import type { AsistenciaFila } from '../services/asistenciasService'
import { sortList, type SortState } from './listSort'
import type { ExportTable } from './queryExport'

export interface AttendanceFilters {
  assignment: string | null; search: string; status: string; from: string; until: string
}

export const attendanceOf = (row: AsistenciaFila) => Array.isArray(row.asistencia) ? row.asistencia[0] : row.asistencia
export const attendancePerson = (row: AsistenciaFila) => [row.usuario?.nombres, row.usuario?.apellido_paterno, row.usuario?.apellido_materno].filter(Boolean).join(' ')
export const attendanceState = (row: AsistenciaFila) => attendanceOf(row)?.estado === 'NO_REQUERIDA' ? 'No requerida' : attendanceOf(row)?.estado ?? 'Sin registro'

/** Selector único para la tabla y los archivos; conserva la búsqueda existente. */
export function attendanceView(rows: AsistenciaFila[], filters: AttendanceFilters, sort: SortState) {
  const filtered = rows.filter(row => (!filters.assignment || row.asignacion_id === filters.assignment)
    && (!filters.status || attendanceOf(row)?.estado === filters.status)
    && (!filters.from || row.asignacion.fecha >= filters.from) && (!filters.until || row.asignacion.fecha <= filters.until)
    && `${attendancePerson(row)} ${row.asignacion.colegio?.nombre ?? row.asignacion.lugar ?? ''} ${row.asignacion.actividad?.nombre ?? ''}`.toLocaleLowerCase('es-CL').includes(filters.search.toLocaleLowerCase('es-CL')))
  const values = { fecha: (row: AsistenciaFila) => `${row.asignacion.fecha} ${row.asignacion.hora_inicio}`,
    actividad: (row: AsistenciaFila) => row.asignacion.actividad?.nombre,
    colegio: (row: AsistenciaFila) => row.asignacion.colegio?.nombre ?? row.asignacion.lugar, nombre: attendancePerson }
  return { filtered, ordered: sortList(filtered, values[sort.key as keyof typeof values], sort.direction) }
}

/** Reemplaza solo las fechas/instancia consultadas; conserva el resto al limpiar filtros. */
export function mergeAttendanceSnapshot(previous: AsistenciaFila[], fresh: AsistenciaFila[], filters: AttendanceFilters) {
  const ids = new Set(fresh.map(row => row.id))
  return [...previous.filter(row => !ids.has(row.id) && !((!filters.assignment || row.asignacion_id === filters.assignment)
    && (!filters.from || row.asignacion.fecha >= filters.from) && (!filters.until || row.asignacion.fecha <= filters.until))), ...fresh]
}

function locationText(row: AsistenciaFila) {
  const item = attendanceOf(row)
  if (!item) return ''
  return [item.direccion_detectada,
    item.latitud != null && item.longitud != null ? `Ver ubicación: https://www.google.com/maps?q=${item.latitud},${item.longitud}` : '',
    item.latitud != null && item.longitud != null ? `Precisión: ${item.precision_gps == null ? 'No informada' : `±${Math.round(item.precision_gps)} m`}` : '',
    item.motivo, item.motivo_regularizacion ? `Regularización: ${item.motivo_regularizacion}` : ''].filter(Boolean).join('\n')
}

export function attendanceExportTable(rows: AsistenciaFila[], filters: AttendanceFilters, sort: SortState, generatedAt: string, personal: boolean): ExportTable {
  if (filters.from && filters.until && filters.from > filters.until) throw new Error('La fecha desde debe ser anterior o igual a la fecha hasta.')
  const labels: Record<string, string> = { fecha: 'Fecha', actividad: 'Actividad', colegio: 'Colegio / lugar', nombre: 'Participante' }
  const criteria = [personal ? 'Mis asistencias' : 'Todas las asistencias', filters.assignment && 'Instancia seleccionada',
    filters.search && `Buscar: ${filters.search}`, filters.status && `Estado: ${filters.status === 'NO_REQUERIDA' ? 'No requerida' : filters.status}`,
    filters.from && `Desde: ${filters.from}`, filters.until && `Hasta: ${filters.until}`].filter(Boolean).join(' · ')
  return { title: personal ? 'Mis asistencias' : 'Asistencia', fileName: personal ? 'mis_asistencias' : 'asistencias',
    generatedAt, filters: criteria, order: `${labels[sort.key]} ${sort.direction === 'asc' ? 'ascendente' : 'descendente'}`,
    columns: ['Fecha', 'Actividad', 'Colegio / lugar', 'Participante', 'Participación', 'Asistencia', 'Ubicación / motivo'],
    columnWidths: [16, 28, 30, 36, 20, 20, 55],
    rows: attendanceView(rows, filters, sort).ordered.map(row => [row.asignacion.fecha.split('-').reverse().join('/'),
      row.asignacion.actividad?.nombre ?? '', row.asignacion.colegio?.nombre ?? row.asignacion.lugar ?? '',
      attendancePerson(row), row.estado.codigo, attendanceState(row), locationText(row)]),
  }
}
