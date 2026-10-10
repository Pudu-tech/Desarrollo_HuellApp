import { useEffect, useState } from 'react'
import { getAsistenciaPropia, reportAsistencia, type Asistencia } from '../../services/asistenciasService'
import type { ParticipacionPropia } from '../../services/participacionesService'
import { useConfirmation } from '../../hooks/useConfirmation'
import { useVisibleRefresh } from '../../hooks/useVisibleRefresh'

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
  useVisibleRefresh(async (isActive) => {
    try {
      const data = await getAsistenciaPropia(info.asignacion_id)
      if (isActive()) { setAttendance(data); setError('') }
    } catch { /* El registro confirmado permanece visible si falla una lectura temporal. */ }
  }, !busy && !location && !motivo)
  async function refresh() {
    setBusy(true)
    try { setAttendance(await getAsistenciaPropia(info.asignacion_id)); setError('') }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible consultar el registro.') }
    finally { setBusy(false) }
  }
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
      setLocation(null); setMotivo('')
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible registrar asistencia.') }
    finally { setBusy(false) }
  }
  const latitude = location?.coords.latitude ?? attendance?.latitud
  const longitude = location?.coords.longitude ?? attendance?.longitud
  const timestamp = (value: string) => new Date(value).toLocaleString('es-CL', { timeZone: 'America/Santiago', dateStyle: 'short', timeStyle: 'medium' })
  return <section className="assignments-form-section"><div className="assignments-panel-heading"><h3>Mi asistencia</h3><button type="button" className="assignments-secondary" disabled={busy} onClick={() => void refresh()}>Actualizar registro</button></div>
    <p>Estado: {attendance?.estado ?? 'Cargando…'}</p>
    {attendance && attendance.estado !== 'PENDIENTE' && <>
      <p className="assignments-success" role="status">Tu asistencia está registrada en HuellApp.</p>
      <dl className="assignments-detail-grid">
        {attendance.fecha_informe && <div><dt>Fecha y hora del último informe</dt><dd>{timestamp(attendance.fecha_informe)}</dd></div>}
        {attendance.fecha_geolocalizacion && <div><dt>Ubicación capturada el</dt><dd>{timestamp(attendance.fecha_geolocalizacion)}</dd></div>}
        {attendance.motivo_regularizacion && <div><dt>Regularización administrativa</dt><dd>{attendance.motivo_regularizacion}</dd></div>}
      </dl>
      <p>Puedes volver a consultar este registro desde tu asignación. Las correcciones administrativas quedan en auditoría.</p>
    </>}
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
