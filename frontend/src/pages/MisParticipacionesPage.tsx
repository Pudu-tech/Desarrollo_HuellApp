/**
 * HuellApp · Listado de participaciones propias.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Consultar, filtrar y ordenar las actividades asignadas al usuario.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Vista personal reutilizada para distintos roles y rutas del monitor.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import SortableHeader from '../components/common/SortableHeader'
import { useListSort } from '../hooks/useListSort'
import { dateSortValue } from '../utils/listSort'
import LoadingIndicator from '../components/LoadingIndicator'
import { useAuth } from '../contexts/AuthContext'
import { clearReadCache } from '../services/readCache'

import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { listMisParticipaciones, type ParticipacionPropia } from '../services/participacionesService'
import '../styles/asignaciones.css'

export default function MisParticipacionesPage({ monitor = false }: { monitor?: boolean }) {
  const { user } = useAuth()
  const [params] = useSearchParams()
  const [result, setResult] = useState<{ rows?: ParticipacionPropia[]; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  const sorting = useListSort<string>(params.get('orden') === 'proximas' ? 'fecha' : 'recibida', params.get('orden') === 'proximas' ? 'asc' : 'desc')
  const order = sorting.sort.key === 'fecha' && sorting.sort.direction === 'asc' ? 'proximas' : sorting.sort.key === 'recibida' && sorting.sort.direction === 'desc' ? 'recientes' : 'personalizado'
  const [pendingOnly, setPendingOnly] = useState(params.get('pendientes') === '1')
  const [search, setSearch] = useState('')
  const [activityFilter, setActivityFilter] = useState('')
  const [placeFilter, setPlaceFilter] = useState('')
  const [responseFilter, setResponseFilter] = useState('')
  const [attendanceFilter, setAttendanceFilter] = useState('')
  const [from, setFrom] = useState('')
  const [until, setUntil] = useState('')
  const allRows = result?.rows ?? []
  const normalize = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es-CL').trim()
  const options = (values: string[]) => [...new Set(values.filter(Boolean))].sort((a, b) => a.localeCompare(b, 'es-CL'))
  const invalidRange = !!from && !!until && from > until
  const hasFilters = !!(search || activityFilter || placeFilter || responseFilter || attendanceFilter || from || until || pendingOnly)
  const rows = sorting.order(allRows.filter((info) => {
    if (invalidRange) return false
    if (pendingOnly && !info.admite_respuesta) return false
    if (activityFilter && info.actividad !== activityFilter) return false
    if (placeFilter && (info.colegio || info.lugar || '') !== placeFilter) return false
    if (responseFilter && info.estado !== responseFilter) return false
    if (attendanceFilter && (info.asistencia_estado || 'SIN_REGISTRO') !== attendanceFilter) return false
    if (from && info.fecha < from) return false
    if (until && info.fecha > until) return false
    return normalize([info.actividad, info.colegio, info.lugar, info.curso, info.asignatura, info.observacion].filter(Boolean).join(' ')).includes(normalize(search))
  }), { fecha: r => `${r.fecha} ${r.hora_inicio}`, recibida: r => dateSortValue(r.ultima_invitacion_at ?? r.recibida_at), actividad: r => r.actividad, colegio: r => r.colegio ?? r.lugar })
  const stateLabel = (value: string) => value === 'SIN_REGISTRO' ? 'Sin registro' : value.charAt(0) + value.slice(1).toLowerCase().replace(/_/g, ' ')
  const timestamp = (value: string | null) => value ? new Date(value).toLocaleString('es-CL', { timeZone: 'America/Santiago', dateStyle: 'short', timeStyle: 'short' }) : 'No disponible'
  useEffect(() => {
    const refresh = () => { if (!document.hidden) setRevision((value) => value + 1) }
    const timer = window.setInterval(refresh, 15000)
    window.addEventListener('focus', refresh)
    document.addEventListener('visibilitychange', refresh)
    return () => {
      window.clearInterval(timer)
      window.removeEventListener('focus', refresh)
      document.removeEventListener('visibilitychange', refresh)
    }
  }, [])
  useEffect(() => {
    let active = true
    void listMisParticipaciones().then((rows) => { if (active) setResult({ rows }) })
      .catch((cause) => { if (active) setResult({ error: cause instanceof Error ? cause.message : 'No fue posible cargar tus participaciones.' }) })
    return () => { active = false }
  }, [revision])
  return <section className="assignments-page"><header className="assignments-heading"><div><h1>Mis instancias</h1><p>Consulta y responde tus participaciones.</p></div>
    <button className="assignments-secondary" onClick={() => { clearReadCache(); setResult(null); setRevision((value) => value + 1) }}>Actualizar</button></header>
    {user?.role_code !== 'SUPERADMIN' && <div className="assignments-personal-toolbar assignments-personal-filters" role="search" aria-label="Filtrar mis instancias">
      <label>Buscar<input type="search" placeholder="Actividad, colegio, lugar o curso..." value={search} onChange={(event) => setSearch(event.target.value)} /></label>
      <label>Actividad<select value={activityFilter} onChange={(event) => setActivityFilter(event.target.value)}><option value="">Todas las actividades</option>{options(allRows.map((row) => row.actividad)).map((value) => <option key={value}>{value}</option>)}</select></label>
      <label>Colegio / lugar<select value={placeFilter} onChange={(event) => setPlaceFilter(event.target.value)}><option value="">Todos los colegios y lugares</option>{options(allRows.map((row) => row.colegio || row.lugar || '')).map((value) => <option key={value}>{value}</option>)}</select></label>
      <label>Mi respuesta<select value={responseFilter} onChange={(event) => { setResponseFilter(event.target.value); setPendingOnly(false) }}><option value="">Todas las respuestas</option>{options(allRows.map((row) => row.estado)).map((value) => <option key={value} value={value}>{stateLabel(value)}</option>)}</select></label>
      <label>Mi asistencia<select value={attendanceFilter} onChange={(event) => setAttendanceFilter(event.target.value)}><option value="">Todos los estados</option>{options(allRows.map((row) => row.asistencia_estado || 'SIN_REGISTRO')).map((value) => <option key={value} value={value}>{stateLabel(value)}</option>)}</select></label>
      <label>Desde<input type="date" value={from} aria-invalid={invalidRange} onChange={(event) => setFrom(event.target.value)} /></label>
      <label>Hasta<input type="date" value={until} aria-invalid={invalidRange} onChange={(event) => setUntil(event.target.value)} /></label>
      <label>Ordenar por<select value={order} onChange={(event) => sorting.setSort(event.target.value === 'proximas' ? { key: 'fecha', direction: 'asc' } : { key: 'recibida', direction: 'desc' })}><option value="personalizado" disabled>Orden de columnas</option><option value="recientes">Más recientes</option><option value="proximas">Próximas actividades</option></select></label>
      <label className="assignments-personal-pending"><input type="checkbox" checked={pendingOnly} onChange={(event) => { setPendingOnly(event.target.checked); setResponseFilter('') }} /> Solo pendientes de respuesta ({allRows.filter((info) => info.admite_respuesta).length})</label>
      <button type="button" className="assignments-secondary" disabled={!hasFilters} onClick={() => { setSearch(''); setActivityFilter(''); setPlaceFilter(''); setResponseFilter(''); setAttendanceFilter(''); setFrom(''); setUntil(''); setPendingOnly(false) }}>Limpiar filtros</button>
    </div>}
    {invalidRange && <p className="assignments-error" role="alert">La fecha desde no puede ser posterior a la fecha hasta.</p>}
    {result?.rows && <p className="assignments-filter-count" role="status">{rows.length} de {allRows.length} instancias</p>}
    <div className="assignments-panel">{!result ? <LoadingIndicator /> : result.error ? <p className="assignments-error" role="alert">{result.error}</p>
      : !rows.length ? <p className="assignments-feedback">{allRows.length ? 'No hay instancias que coincidan con los filtros.' : 'No tienes participaciones registradas.'}</p>
      : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><SortableHeader label="Actividad" column="actividad" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Recibida / actualizada" column="recibida" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Fecha de la actividad" column="fecha" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Colegio / lugar" column="colegio" sort={sorting.sort} onSort={sorting.toggle} /><th>Mi respuesta</th><th>Mi asistencia</th><th>Acciones</th></tr></thead><tbody>
        {rows.map((info) => <tr key={info.participante_id}><td>{info.actividad}</td><td><div>Recibida: {timestamp(info.recibida_at)}</div>{info.actualizada_at && <div>Actualizada: {timestamp(info.actualizada_at)}</div>}</td><td>{info.fecha.split('-').reverse().join('/')}</td><td>{info.colegio ?? info.lugar}</td><td><span className={`assignments-status assignments-status--${info.estado.toLowerCase()}`}>{info.admite_respuesta ? 'Pendiente de respuesta' : info.estado}</span></td>
          <td><span className={`assignments-status assignments-status--${info.asistencia_estado?.toLowerCase() ?? 'unknown'}`}>{info.asistencia_estado ? info.asistencia_estado === 'NO_REQUERIDA' ? 'No requerida' : info.asistencia_estado.charAt(0) + info.asistencia_estado.slice(1).toLowerCase() : 'Sin registro'}</span></td>
          <td><Link className="assignments-action" to={`${monitor ? '/app/monitor/asignaciones' : '/app/mis-asignaciones'}/${info.asignacion_id}`}>Ver instancia</Link></td></tr>)}
      </tbody></table></div>}</div>
  </section>
}
