import { useEffect, useState } from 'react'
import LoadingIndicator from '../components/LoadingIndicator'
import { Link, useSearchParams } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { useConfirmation } from '../hooks/useConfirmation'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import { listAsistencias, listMisAsistencias, regularizarAsistencia, type AsistenciaFila } from '../services/asistenciasService'
import '../styles/asignaciones.css'

export default function AsistenciaPage() {
  const { user } = useAuth()
  const [ownOnly, setOwnOnly] = useState(false)
  const canSwitchView = ['DIRECTIVA', 'COORDINADOR'].includes(user?.role_code ?? '')
  const personal = user?.role_code === 'MONITOR' || (canSwitchView && ownOnly)
  const [params] = useSearchParams()
  const assignmentFilter = params.get('asignacion')
  const { confirm, confirmationDialog } = useConfirmation()
  const [rows, setRows] = useState<AsistenciaFila[] | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState(() => ['PENDIENTE','PRESENTE','AUSENTE','JUSTIFICADA','NO_REQUERIDA'].includes(params.get('estado') || '') ? params.get('estado')! : '')
  const [from, setFrom] = useState('')
  const [until, setUntil] = useState('')
  const [editing, setEditing] = useState<AsistenciaFila | null>(null)
  const [estado, setEstado] = useState('PRESENTE')
  const [motivo, setMotivo] = useState('')
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState('')
  const load = personal ? listMisAsistencias : listAsistencias
  const canEdit = !personal && ['SUPERADMIN', 'DIRECTIVA'].includes(user?.role_code ?? '')
  const attendance = (row: AsistenciaFila) => Array.isArray(row.asistencia) ? row.asistencia[0] : row.asistencia
  const person = (row: AsistenciaFila) => [row.usuario?.nombres, row.usuario?.apellido_paterno, row.usuario?.apellido_materno].filter(Boolean).join(' ')
  useEffect(() => {
    let active = true
    void load().then((data) => { if (active) { setRows(data); setError('') } }).catch((cause: Error) => { if (active) setError(cause.message) })
    return () => { active = false }
  }, [load])
  function selectView(own: boolean) {
    if (busy || editing || own === ownOnly) return
    setOwnOnly(own); setRows(null); setError(''); setNotice('')
    setSearch(''); setStatus(''); setFrom(''); setUntil('')
  }
  useVisibleRefresh(async (isActive) => {
    try { const data = await load(); if (isActive()) { setRows(data); setError('') } }
    catch { /* Conserva el listado durante fallos temporales. */ }
  }, !editing && !busy, 30000)
  async function refresh() {
    try { setRows(await load()); setError('') } catch (cause) { setError(cause instanceof Error ? cause.message : 'No se pudo actualizar.') }
  }
  async function save() {
    if (!editing || busy || reason.trim().length < 3 || (estado !== 'PRESENTE' && !motivo.trim())) return
    if (!await confirm({ title: 'Regularizar asistencia', confirmLabel: 'Guardar regularización', message: `Se actualizará la asistencia de ${person(editing)}. El motivo y el cambio quedarán registrados en auditoría; la ubicación original se conservará.` })) return
    setBusy(true); setError('')
    try {
      await regularizarAsistencia(editing.asignacion_id, editing.id, { estado, motivo: estado === 'PRESENTE' ? null : motivo.trim(), motivo_regularizacion: reason.trim() })
      setEditing(null); setNotice('Asistencia regularizada y registrada en auditoría.'); await refresh()
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible regularizar.') }
    finally { setBusy(false) }
  }
  const filtered = (rows ?? []).filter((row) => (!assignmentFilter || row.asignacion_id === assignmentFilter) && (!status || attendance(row)?.estado === status)
    && (!from || row.asignacion.fecha >= from) && (!until || row.asignacion.fecha <= until)
    && `${person(row)} ${row.asignacion.colegio?.nombre ?? row.asignacion.lugar ?? ''} ${row.asignacion.actividad?.nombre ?? ''}`.toLocaleLowerCase('es-CL').includes(search.toLocaleLowerCase('es-CL')))
  return <section className="assignments-page"><header className="assignments-heading"><div><h1>Asistencia</h1><p>Asistencia efectiva de los participantes, independiente de su respuesta a la invitación.</p></div><button className="assignments-secondary" disabled={busy || !!editing} onClick={() => void refresh()}>Actualizar</button></header>
    {error && <p className="assignments-error" role="alert">{error}</p>}{notice && <p className="assignments-success" role="status">{notice}</p>}
    {canSwitchView && <div className="assignments-editor-actions" role="group" aria-label="Vista de asistencia">
      <button type="button" className={personal ? 'assignments-secondary' : 'assignments-primary'} aria-pressed={!personal} disabled={busy || !!editing} onClick={() => selectView(false)}>Todas las asistencias</button>
      <button type="button" className={personal ? 'assignments-primary' : 'assignments-secondary'} aria-pressed={personal} disabled={busy || !!editing} onClick={() => selectView(true)}>Mis asistencias</button>
    </div>}
    {personal && <p className="assignments-feedback">Estás consultando únicamente tus registros de asistencia.</p>}
    {assignmentFilter && <p>Mostrando asistencia de la asignación seleccionada. <Link to="/app/asistencia">Ver todas</Link></p>}
    <div className="assignments-panel"><div className="assignments-form-grid"><label>Participante, colegio o actividad<input value={search} onChange={(e) => setSearch(e.target.value)} /></label><label>Estado<select value={status} onChange={(e) => setStatus(e.target.value)}><option value="">Todos</option>{['PENDIENTE','PRESENTE','AUSENTE','JUSTIFICADA','NO_REQUERIDA'].map((value) => <option key={value} value={value}>{value === 'NO_REQUERIDA' ? 'No requerida' : value}</option>)}</select></label><label>Desde<input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label><label>Hasta<input type="date" value={until} onChange={(e) => setUntil(e.target.value)} /></label></div></div>
    {editing && <div className="assignments-panel"><h2>Regularizar: {person(editing)}</h2><div className="assignments-form-grid"><label>Estado<select disabled={busy} value={estado} onChange={(e) => setEstado(e.target.value)}>{['PRESENTE','AUSENTE','JUSTIFICADA'].map((value) => <option key={value} value={value}>{value === 'NO_REQUERIDA' ? 'No requerida' : value}</option>)}</select></label>{estado !== 'PRESENTE' && <label>Motivo de ausencia<textarea maxLength={1000} disabled={busy} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></label>}<label>Motivo de regularización (obligatorio)<textarea maxLength={1000} disabled={busy} value={reason} onChange={(e) => setReason(e.target.value)} /></label></div><div className="assignments-editor-actions"><button className="assignments-primary" disabled={busy || reason.trim().length < 3 || (estado !== 'PRESENTE' && !motivo.trim())} onClick={() => void save()}>Guardar regularización</button><button className="assignments-secondary" disabled={busy} onClick={() => setEditing(null)}>Cerrar</button></div></div>}
    <div className="assignments-panel">{!rows ? error ? <p>No se pudo cargar la asistencia. Pulsa Actualizar para reintentar.</p> : <LoadingIndicator /> : !filtered.length ? <p>No hay asistencias para estos filtros.</p> : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th>Actividad / fecha</th><th>Colegio / lugar</th><th>Participante</th><th>Participación</th><th>Asistencia</th><th>Ubicación / motivo</th><th>Acciones</th></tr></thead><tbody>{filtered.map((row) => {
      const item = attendance(row)
      return <tr key={row.id}><td>{row.asignacion.actividad?.nombre}<br />{row.asignacion.fecha.split('-').reverse().join('/')}</td><td>{row.asignacion.colegio?.nombre ?? row.asignacion.lugar}</td><td>{person(row)}</td><td>{row.estado.codigo}</td><td>{item?.estado === 'NO_REQUERIDA' ? 'No requerida' : item?.estado ?? 'Sin registro'}</td><td>{item?.direccion_detectada}{item?.latitud != null && item.longitud != null && <><br /><a target="_blank" rel="noreferrer" href={`https://www.google.com/maps?q=${item.latitud},${item.longitud}`}>Ver ubicación</a><br />Precisión: {item.precision_gps == null ? 'No informada' : `±${Math.round(item.precision_gps)} m`}</>}{item?.motivo && <p>{item.motivo}</p>}{item?.motivo_regularizacion && <p>Regularización: {item.motivo_regularizacion}</p>}</td><td>{canEdit && item && row.estado.codigo === 'ACEPTADA' && <button className="assignments-secondary" disabled={busy} onClick={() => { setEditing(row); setEstado(item.estado === 'PENDIENTE' ? 'PRESENTE' : item.estado); setMotivo(item.motivo ?? ''); setReason(''); setError('') }}>Regularizar</button>}</td></tr>
    })}</tbody></table></div>}</div>{confirmationDialog}
  </section>
}
