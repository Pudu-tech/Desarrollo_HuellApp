import { useEffect, useState } from 'react'
import AttendanceCard from './AttendanceCard'
import LoadingIndicator from '../LoadingIndicator'
import { getMiParticipacion, type ParticipacionPropia } from '../../services/participacionesService'

/** Reutiliza el registro propio con ubicación y las validaciones del backend. */
export default function OwnAttendancePanel({ assignmentId, onClose, onSaved }: {
  assignmentId: string; onClose: () => void; onSaved: () => void
}) {
  const [info, setInfo] = useState<ParticipacionPropia | null>(null)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    void getMiParticipacion(assignmentId).then((data) => { if (active) setInfo(data) })
      .catch((cause) => { if (active) setError(cause instanceof Error ? cause.message : 'No se pudo cargar tu asistencia.') })
    return () => { active = false }
  }, [assignmentId, revision])
  return <div className="assignments-panel" role="region" aria-label="Registrar mi asistencia">
    <div className="assignments-panel-heading"><h2>Registrar mi asistencia</h2><button type="button" className="assignments-secondary" onClick={onClose}>Cerrar</button></div>
    {error ? <><p className="assignments-error" role="alert">{error}</p><button type="button" className="assignments-secondary" onClick={() => { setError(''); setRevision((value) => value + 1) }}>Reintentar</button></>
      : !info ? <LoadingIndicator /> : <><p><strong>{info.actividad}</strong> · {info.fecha.split('-').reverse().join('/')} · {info.colegio || info.lugar}</p><AttendanceCard info={info} onSaved={onSaved} /></>}
  </div>
}
