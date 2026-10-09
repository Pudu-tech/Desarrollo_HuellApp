/** Estado propio y confirmación común. Aceptar una invitación no marca asistencia. */
import { useRef, useState } from 'react'
import { useConfirmation } from '../../hooks/useConfirmation'
import { responderInvitacion, responderMiParticipacion, type ParticipacionPropia, type RespuestaParticipacion } from '../../services/participacionesService'

interface Props { info: ParticipacionPropia; token?: string; initialAction?: string; onUpdate: () => void }

export default function ParticipationCard({ info, token, initialAction, onUpdate }: Props) {
  const [action, setAction] = useState<RespuestaParticipacion['accion']>(initialAction === 'REJECT' ? 'REJECT' : 'ACCEPT')
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const submitting = useRef(false)
  const [answered, setAnswered] = useState<string | null>(null)
  const [error, setError] = useState('')
  const { confirm, confirmationDialog } = useConfirmation()
  const state = answered ?? info.estado
  const canRespond = state === 'PENDIENTE' && info.admite_respuesta

  async function submit() {
    if (submitting.current || !canRespond) return
    if (action === 'REJECT' && !reason.trim()) { setError('Indica el motivo del rechazo.'); return }
    submitting.current = true; setBusy(true); setError('')
    try {
      if (!await confirm({ title: action === 'ACCEPT' ? '¿Aceptar participación?' : '¿Rechazar participación?',
        confirmLabel: action === 'ACCEPT' ? 'Sí, aceptar' : 'Sí, rechazar',
        message: 'Tu respuesta quedará registrada y se compartirá con todos los canales. No tendrás que responder nuevamente.' })) return
      const datos = { accion: action, motivo: action === 'REJECT' ? reason.trim() : null }
      const result = token ? await responderInvitacion(token, datos) : await responderMiParticipacion(info.asignacion_id, datos)
      setAnswered(result.estado); onUpdate()
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible responder.'); onUpdate() }
    finally { submitting.current = false; setBusy(false) }
  }

  return <section className="assignments-form-section">
    <h3>Mi participación</h3>
    {state === 'ACEPTADA' ? <p className="assignments-success" role="status">Ya aceptaste esta asignación. No necesitas responder desde otro canal.</p>
      : state === 'RECHAZADA' ? <p className="assignments-warning" role="status">Ya rechazaste esta asignación. No necesitas responder desde otro canal.</p>
      : <p>Estado: <strong>{state === 'PENDIENTE' ? 'Pendiente de respuesta' : state}</strong></p>}
    {info.motivo_rechazo && <p>Motivo: {info.motivo_rechazo}</p>}
    {error && <p className="assignments-error" role="alert">{error}</p>}
    {canRespond && <fieldset className="assignments-fieldset" disabled={busy}>
      <label>Respuesta<select value={action} onChange={(event) => setAction(event.target.value as RespuestaParticipacion['accion'])}><option value="ACCEPT">Aceptar participación</option><option value="REJECT">Rechazar participación</option></select></label>
      {action === 'REJECT' && <label>Motivo del rechazo<textarea required maxLength={1000} rows={3} value={reason} onChange={(event) => setReason(event.target.value)} /></label>}
      <div className="assignments-editor-actions"><button className="assignments-primary" type="button" onClick={() => void submit()}>{busy ? 'Procesando…' : 'Confirmar respuesta'}</button></div>
    </fieldset>}
    {state === 'PENDIENTE' && !info.admite_respuesta && <p className="assignments-warning">Esta asignación ya no admite respuestas.</p>}
    <p>Aceptar confirma tu participación. La asistencia se registra por separado desde Mis asignaciones.</p>
    {confirmationDialog}
  </section>
}
