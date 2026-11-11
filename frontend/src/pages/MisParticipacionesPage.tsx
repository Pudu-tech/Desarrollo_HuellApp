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
import { clearReadCache } from '../services/readCache'

import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { listMisParticipaciones, type ParticipacionPropia } from '../services/participacionesService'
import '../styles/asignaciones.css'

export default function MisParticipacionesPage({ monitor = false }: { monitor?: boolean }) {
  const [params] = useSearchParams()
  const [result, setResult] = useState<{ rows?: ParticipacionPropia[]; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  const sorting = useListSort<string>(params.get('orden') === 'proximas' ? 'fecha' : 'recibida', params.get('orden') === 'proximas' ? 'asc' : 'desc')
  const order = sorting.sort.key === 'fecha' && sorting.sort.direction === 'asc' ? 'proximas' : sorting.sort.key === 'recibida' && sorting.sort.direction === 'desc' ? 'recientes' : 'personalizado'
  const [pendingOnly, setPendingOnly] = useState(params.get('pendientes') === '1')
  const rows = sorting.order((result?.rows ?? []).filter(info => !pendingOnly || info.admite_respuesta), { fecha: r => `${r.fecha} ${r.hora_inicio}`, recibida: r => dateSortValue(r.ultima_invitacion_at ?? r.recibida_at), actividad: r => r.actividad, colegio: r => r.colegio ?? r.lugar })
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
    <div className="assignments-personal-toolbar">
      <label>Ordenar por<select value={order} onChange={(event) => sorting.setSort(event.target.value === 'proximas' ? { key: 'fecha', direction: 'asc' } : { key: 'recibida', direction: 'desc' })}><option value="personalizado" disabled>Orden de columnas</option><option value="recientes">Más recientes</option><option value="proximas">Próximas actividades</option></select></label>
      <label><input type="checkbox" checked={pendingOnly} onChange={(event) => setPendingOnly(event.target.checked)} /> Solo pendientes de respuesta ({result?.rows?.filter((info) => info.admite_respuesta).length ?? 0})</label>
    </div>
    <div className="assignments-panel">{!result ? <LoadingIndicator /> : result.error ? <p className="assignments-error" role="alert">{result.error}</p>
      : !rows.length ? <p className="assignments-feedback">{pendingOnly ? 'No tienes participaciones pendientes de respuesta.' : 'No tienes participaciones registradas.'}</p>
      : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><SortableHeader label="Actividad" column="actividad" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Recibida / actualizada" column="recibida" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Fecha de la actividad" column="fecha" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Colegio / lugar" column="colegio" sort={sorting.sort} onSort={sorting.toggle} /><th>Mi respuesta</th><th>Mi asistencia</th><th>Acciones</th></tr></thead><tbody>
        {rows.map((info) => <tr key={info.participante_id}><td>{info.actividad}</td><td><div>Recibida: {timestamp(info.recibida_at)}</div>{info.actualizada_at && <div>Actualizada: {timestamp(info.actualizada_at)}</div>}</td><td>{info.fecha.split('-').reverse().join('/')}</td><td>{info.colegio ?? info.lugar}</td><td><span className={`assignments-status assignments-status--${info.estado.toLowerCase()}`}>{info.admite_respuesta ? 'Pendiente de respuesta' : info.estado}</span></td>
          <td><span className={`assignments-status assignments-status--${info.asistencia_estado?.toLowerCase() ?? 'unknown'}`}>{info.asistencia_estado ? info.asistencia_estado === 'NO_REQUERIDA' ? 'No requerida' : info.asistencia_estado.charAt(0) + info.asistencia_estado.slice(1).toLowerCase() : 'Sin registro'}</span></td>
          <td><Link className="assignments-action" to={`${monitor ? '/app/monitor/asignaciones' : '/app/mis-asignaciones'}/${info.asignacion_id}`}>Ver instancia</Link></td></tr>)}
      </tbody></table></div>}</div>
  </section>
}
