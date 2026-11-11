/**
 * HuellApp · Detalle de una participación propia.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Consultar la instancia personal y permitir responder o registrar asistencia.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Reutiliza los componentes comunes de datos, participación y asistencia.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import LoadingIndicator from '../components/LoadingIndicator'
/** Detalle propio real. Refresca al volver y cada 30 s para respuestas por correo. */
import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import ParticipationCard from '../components/asignaciones/ParticipationCard'
import AttendanceCard from '../components/asignaciones/AttendanceCard'
import PersonalAssignmentInfo from '../components/asignaciones/PersonalAssignmentInfo'
import { getMiParticipacion, type ParticipacionPropia } from '../services/participacionesService'
import '../styles/asignaciones.css'

export default function MiParticipacionPage({ monitor = false }: { monitor?: boolean }) {
  const { asignacionId = '' } = useParams()
  const [result, setResult] = useState<{ id: string; info?: ParticipacionPropia; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    void getMiParticipacion(asignacionId).then((info) => { if (active) setResult({ id: asignacionId, info }) })
      .catch((cause) => { if (active) setResult({ id: asignacionId, error: cause instanceof Error ? cause.message : 'No fue posible cargar la instancia.' }) })
    return () => { active = false }
  }, [asignacionId, revision])
  useEffect(() => {
    const refresh = () => { if (!document.hidden) setRevision((value) => value + 1) }
    const timer = window.setInterval(refresh, 30_000)
    window.addEventListener('focus', refresh)
    return () => { window.clearInterval(timer); window.removeEventListener('focus', refresh) }
  }, [])
  const current = result?.id === asignacionId ? result : null
  return <section className="assignments-page"><header className="assignments-heading"><div><h1>Mi instancia</h1><p>Tu respuesta es la misma en todos los canales.</p></div>
    <Link className="assignments-action" to={monitor ? '/app/monitor/asignaciones' : '/app/mis-asignaciones'}>Volver a mis instancias</Link></header>
    <div className="assignments-panel">{!current ? <LoadingIndicator /> : current.error ? <p className="assignments-error" role="alert">{current.error}</p>
      : current.info && <><PersonalAssignmentInfo info={current.info} /><ParticipationCard key={current.info.invitacion_version} info={current.info} onUpdate={() => setRevision((value) => value + 1)} /><AttendanceCard key={current.info.participante_id} info={current.info} /></>}</div>
  </section>
}
