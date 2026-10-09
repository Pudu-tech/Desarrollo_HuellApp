import { clearReadCache } from '../services/readCache'
/** HuellApp · Actividades propias para monitor, coordinador y directiva. */
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { listMisParticipaciones, type ParticipacionPropia } from '../services/participacionesService'
import '../styles/asignaciones.css'

export default function MisParticipacionesPage({ monitor = false }: { monitor?: boolean }) {
  const [result, setResult] = useState<{ rows?: ParticipacionPropia[]; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  const [order, setOrder] = useState('recientes')
  const [pendingOnly, setPendingOnly] = useState(false)
  const rows = [...(result?.rows ?? [])].filter((info) => !pendingOnly || info.admite_respuesta).sort((a, b) =>
    order === 'proximas' ? `${a.fecha} ${a.hora_inicio}`.localeCompare(`${b.fecha} ${b.hora_inicio}`)
      : (b.ultima_invitacion_at ?? '').localeCompare(a.ultima_invitacion_at ?? ''))
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
  return <section className="assignments-page"><header className="assignments-heading"><div><h1>Mis asignaciones</h1><p>Consulta y responde tus participaciones.</p></div>
    <button className="assignments-secondary" onClick={() => { clearReadCache(); setResult(null); setRevision((value) => value + 1) }}>Actualizar</button></header>
    <div className="assignments-personal-toolbar">
      <label>Ordenar por<select value={order} onChange={(event) => setOrder(event.target.value)}><option value="recientes">Más recientes</option><option value="proximas">Próximas actividades</option></select></label>
      <label><input type="checkbox" checked={pendingOnly} onChange={(event) => setPendingOnly(event.target.checked)} /> Solo pendientes de respuesta ({result?.rows?.filter((info) => info.admite_respuesta).length ?? 0})</label>
    </div>
    <div className="assignments-panel">{!result ? <p role="status">Cargando…</p> : result.error ? <p className="assignments-error" role="alert">{result.error}</p>
      : !rows.length ? <p className="assignments-feedback">{pendingOnly ? 'No tienes participaciones pendientes de respuesta.' : 'No tienes participaciones registradas.'}</p>
      : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th>Actividad</th><th>Recibida / actualizada</th><th>Fecha de la actividad</th><th>Colegio / lugar</th><th>Mi respuesta</th><th>Acciones</th></tr></thead><tbody>
        {rows.map((info) => <tr key={info.participante_id}><td>{info.actividad}</td><td><div>Recibida: {timestamp(info.recibida_at)}</div>{info.actualizada_at && <div>Actualizada: {timestamp(info.actualizada_at)}</div>}</td><td>{info.fecha.split('-').reverse().join('/')}</td><td>{info.colegio ?? info.lugar}</td><td><span className={`assignments-status assignments-status--${info.estado.toLowerCase()}`}>{info.admite_respuesta ? 'Pendiente de respuesta' : info.estado}</span></td>
          <td><Link className="assignments-action" to={`${monitor ? '/app/monitor/asignaciones' : '/app/mis-asignaciones'}/${info.asignacion_id}`}>Ver asignación</Link></td></tr>)}
      </tbody></table></div>}</div>
  </section>
}
