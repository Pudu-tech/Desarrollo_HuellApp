/** HuellApp · Actividades propias para monitor, coordinador y directiva. */
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { listMisParticipaciones, type ParticipacionPropia } from '../services/participacionesService'
import '../styles/asignaciones.css'

export default function MisParticipacionesPage({ monitor = false }: { monitor?: boolean }) {
  const [result, setResult] = useState<{ rows?: ParticipacionPropia[]; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    void listMisParticipaciones().then((rows) => { if (active) setResult({ rows }) })
      .catch((cause) => { if (active) setResult({ error: cause instanceof Error ? cause.message : 'No fue posible cargar tus participaciones.' }) })
    return () => { active = false }
  }, [revision])
  return <section className="assignments-page"><header className="assignments-heading"><div><h1>Mis asignaciones</h1><p>Consulta y responde tus participaciones.</p></div>
    <button className="assignments-secondary" onClick={() => { setResult(null); setRevision((value) => value + 1) }}>Actualizar</button></header>
    <div className="assignments-panel">{!result ? <p role="status">Cargando…</p> : result.error ? <p className="assignments-error" role="alert">{result.error}</p>
      : !result.rows?.length ? <p className="assignments-feedback">No tienes participaciones registradas.</p>
      : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th>Actividad</th><th>Fecha</th><th>Colegio / lugar</th><th>Mi respuesta</th><th>Acciones</th></tr></thead><tbody>
        {result.rows.map((info) => <tr key={info.participante_id}><td>{info.actividad}</td><td>{info.fecha.split('-').reverse().join('/')}</td><td>{info.colegio ?? info.lugar}</td><td>{info.estado}</td>
          <td><Link className="assignments-action" to={`${monitor ? '/app/monitor/asignaciones' : '/app/mis-asignaciones'}/${info.asignacion_id}`}>Ver asignación</Link></td></tr>)}
      </tbody></table></div>}</div>
  </section>
}
