/** Confirmación personal desde correo. Consultar no responde ni requiere sesión. */
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import ParticipationCard from '../components/asignaciones/ParticipationCard'
import PersonalAssignmentInfo from '../components/asignaciones/PersonalAssignmentInfo'
import { consultarInvitacion, type ParticipacionPropia } from '../services/participacionesService'
import '../styles/asignaciones.css'
import '../styles/auth-pages.css'
import '../styles/invitacion-participacion.css'

export default function InvitacionParticipacionPage() {
  const [link] = useState(() => new URLSearchParams(window.location.hash.slice(1)))
  const token = link.get('token') ?? ''
  const [result, setResult] = useState<{ info?: ParticipacionPropia; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    // Retira la credencial de la barra y del historial; permanece solo en memoria.
    window.history.replaceState(window.history.state, '', window.location.pathname)
    let active = true
    if (token) void consultarInvitacion(token).then((info) => { if (active) setResult({ info }) })
      .catch((cause) => { if (active) setResult({ error: cause instanceof Error ? cause.message : 'No fue posible consultar la invitación.' }) })
    return () => { active = false }
  }, [token, revision])
  return <main className="auth-page">
    <section className="auth-card invitation-card">
    <header className="auth-header"><div className="auth-logo-wrap"><img src="/logo-huella.png" alt="Fundación Huella" className="auth-logo" /></div><p className="auth-brand">HuellApp</p></header>
    <h1 className="auth-title">Responder participación</h1>
    <p className="auth-subtitle">Revisa la actividad y confirma tu respuesta.</p>
    <div className="assignments-page invitation-content">
      {!token ? <p className="assignments-warning">Abre el enlace personal recibido en tu correo.</p>
        : !result ? <p role="status">Consultando invitación…</p>
        : result.error ? <p className="assignments-error" role="alert">{result.error}</p>
        : result.info && <><PersonalAssignmentInfo info={result.info} /><ParticipationCard key={result.info.invitacion_version} info={result.info} token={token} initialAction={link.get('accion') ?? ''} onUpdate={() => setRevision((value) => value + 1)} /></>}
    </div>
    <footer className="auth-footer"><Link className="auth-link" to="/">Ingresar a HuellApp</Link></footer>
    </section>
  </main>
}
