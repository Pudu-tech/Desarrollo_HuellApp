import { useEffect, useState } from 'react'
import { getAsistenciaPropia, reportAsistencia, type Asistencia } from '../../services/asistenciasService'
import type { ParticipacionPropia } from '../../services/participacionesService'
import { useConfirmation } from '../../hooks/useConfirmation'

export default function AttendanceCard({ info }: { info: ParticipacionPropia }) {
  const [attendance, setAttendance] = useState<Asistencia | null>(null)
  const [estado, setEstado] = useState('PRESENTE')
  const [motivo, setMotivo] = useState('')
  const [location, setLocation] = useState<GeolocationPosition | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const { confirm, confirmationDialog } = useConfirmation()
  useEffect(() => {
    let active = true
    void getAsistenciaPropia(info.asignacion_id).then((data) => { if (active) setAttendance(data) })
      .catch((cause: Error) => { if (active) setError(cause.message) })
    return () => { active = false }
  }, [info.asignacion_id])
  function locate() {
    if (!navigator.geolocation) { setError('Este dispositivo no permite obtener ubicación.'); return }
    setBusy(true); setError('')
    navigator.geolocation.getCurrentPosition((position) => { setLocation(position); setBusy(false) },
      (cause) => { setError(cause.code === 1 ? 'Permite el acceso a ubicación para registrar asistencia.' : 'No se pudo obtener la ubicación. Reintenta.'); setBusy(false) },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 })
  }
  async function save() {
    if (!location || busy || (estado !== 'PRESENTE' && !motivo.trim())) return
    if (!await confirm({ title: 'Registrar asistencia', confirmLabel: 'Confirmar asistencia', message: 'Se registrará tu asistencia con la ubicación capturada. Las correcciones posteriores requieren regularización administrativa.' })) return
    setBusy(true); setError('')
    try {
      setAttendance(await reportAsistencia(info.asignacion_id, info.participante_id, {
        estado, motivo: estado === 'PRESENTE' ? null : motivo.trim(), latitud: location.coords.latitude,
        longitud: location.coords.longitude, precision_gps: location.coords.accuracy,
        fecha_geolocalizacion: new Date(location.timestamp).toISOString(),
      }))
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible registrar asistencia.') }
    finally { setBusy(false) }
  }
  const latitude = location?.coords.latitude ?? attendance?.latitud
  const longitude = location?.coords.longitude ?? attendance?.longitud
  return <section className="assignments-form-section"><h3>Mi asistencia</h3>
    <p>Estado: {attendance?.estado ?? 'Cargando…'}</p>
    {error && <p className="assignments-error" role="alert">{error}</p>}
    {latitude != null && longitude != null && <p>Ubicación: {attendance?.direccion_detectada || `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`} · Precisión: ±{Math.round(location?.coords.accuracy ?? attendance?.precision_gps ?? 0)} m · <a href={`https://www.google.com/maps?q=${latitude},${longitude}`} target="_blank" rel="noreferrer">Ver en mapa</a></p>}
    {attendance?.estado === 'PENDIENTE' && (info.estado !== 'ACEPTADA' ? <p>Debes aceptar la participación antes de registrar asistencia.</p> : <>
      <p>Disponible desde el inicio de la actividad hasta 24 horas después de su término. Se solicitará permiso para obtener tu ubicación.</p>
      <div className="assignments-form-grid"><label>Asistencia<select disabled={busy} value={estado} onChange={(e) => setEstado(e.target.value)}><option value="PRESENTE">Presente</option><option value="AUSENTE">Ausente</option><option value="JUSTIFICADA">Justificada</option></select></label>
      {estado !== 'PRESENTE' && <label>Motivo<textarea required maxLength={1000} disabled={busy} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></label>}</div>
      <div className="assignments-editor-actions"><button className="assignments-secondary" disabled={busy} onClick={locate}>Obtener ubicación</button><button className="assignments-primary" disabled={busy || !location || (estado !== 'PRESENTE' && !motivo.trim())} onClick={() => void save()}>{busy ? 'Procesando…' : 'Registrar asistencia'}</button></div>
    </>)}
    {attendance?.motivo && <p>Motivo: {attendance.motivo}</p>}{confirmationDialog}
  </section>
}
