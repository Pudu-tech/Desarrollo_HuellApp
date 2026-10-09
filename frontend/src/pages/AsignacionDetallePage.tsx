import { clearReadCache } from '../services/readCache'
/**
 * HuellApp · Resumen persistido de una asignación de gestión.
 * Consulta el detalle real y conserva el diseño del listado, sin datos de demostración.
 * La edición respeta permisos y solicita reconfirmación sin alterar asistencia histórica.
 */
import { useEffect, useState } from 'react'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { deleteAsignacion, getAsignacion, getCatalogosAsignaciones, getOpcionesEdicion, getOpcionesParticipantes, removeParticipante, reassignParticipante, updateAsignacion } from '../services/asignacionesService'
import { useAuth } from '../contexts/AuthContext'
import { useConfirmation } from '../hooks/useConfirmation'
import { getPermissions } from '../services/recursosService'
import AsignacionCreateForm from '../components/asignaciones/DeferredAsignacionForm'
import AgregarParticipanteForm from '../components/asignaciones/AgregarParticipanteForm'
import { payloadEdicion, cambiosEdicion } from '../components/asignaciones/asignacionEdicion'
import type { AsignacionDetail, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion } from '../types/asignaciones'
import '../styles/asignaciones.css'

export default function AsignacionDetallePage() {
  const { asignacionId = '' } = useParams()
  const { user } = useAuth()
  const navigate = useNavigate()
  const { confirm, confirmationDialog } = useConfirmation()
  const [deleting, setDeleting] = useState(false)
  const [adding, setAdding] = useState(false)
  const [reassignment, setReassignment] = useState<{ participant: string; options: Awaited<ReturnType<typeof getOpcionesParticipantes>>['participantes'] } | null>(null)
  const [newMonitor, setNewMonitor] = useState('')
  const [reassigning, setReassigning] = useState(false)
  const [result, setResult] = useState<{ id: string; item?: AsignacionDetail; catalogos?: CatalogosAsignacion; error?: string } | null>(null)
  const [revision, setRevision] = useState(0)
  const [permissions, setPermissions] = useState<string[]>([])
  const [opciones, setOpciones] = useState<OpcionesCreacion | null>(null)
  const [opening, setOpening] = useState(false)
  const [editError, setEditError] = useState('')
  const [notice, setNotice] = useState('')
  useEffect(() => {
    let active = true
    void Promise.all([getAsignacion(asignacionId), getCatalogosAsignaciones(), getPermissions()])
      .then(([item, catalogos, rights]) => { if (active) { setResult({ id: asignacionId, item, catalogos }); setPermissions(rights) } })
      .catch((cause: unknown) => { if (active) setResult({ id: asignacionId, error: cause instanceof Error ? cause.message : 'No fue posible obtener el detalle.' }) })
    return () => { active = false }
  }, [asignacionId, revision])
  const current = result?.id === asignacionId ? result : null
  const item = current?.item
  const tipo = current?.catalogos?.tipos_actividad.find((entry) => entry.id === item?.tipo_actividad_id)
  const estado = current?.catalogos?.estados.find((entry) => entry.id === item?.estado_id)
  const colegio = current?.catalogos?.colegios.find((entry) => entry.id === item?.colegio_id)
  const canDelete = ['SUPERADMIN', 'DIRECTIVA'].includes(user?.role_code ?? '') && permissions.includes('DELETE_ASSIGNMENT')
  useVisibleRefresh(async (isActive) => {
    try {
      const saved = await getAsignacion(asignacionId, true)
      if (!isActive()) return
      setResult((previous) => previous?.id === asignacionId ? { ...previous, item: saved } : previous)
    } catch { /* Mantiene el detalle ante una falla temporal y reintenta en el siguiente ciclo. */ }
  }, !!item && !opciones && !adding && !reassignment && !reassigning && !deleting && !opening)
  async function removePerson(participant: string, name: string) {
    if (!item || reassigning || deleting) return
    if (!await confirm({ title: 'Quitar participante', confirmLabel: 'Quitar participante',
      message: `Se retirará a ${name} de esta asignación. Su participación y asistencia se conservarán como historial. Las respuestas de las otras personas se conservarán.` })) return
    setReassigning(true); setEditError('')
    try {
      await removeParticipante(item.id, participant)
      const saved = await getAsignacion(item.id)
      setResult({ id: item.id, item: saved, catalogos: current?.catalogos })
      setReassignment(null)
      setNotice('Participante retirado. La asignación dejará de aparecer en su panel y se conserva el historial.')
    } catch (cause) { setEditError(cause instanceof Error ? cause.message : 'No fue posible quitar al participante.') }
    finally { setReassigning(false) }
  }
  async function openReassignment(participant: string) {
    setReassigning(true); setEditError(''); setNewMonitor('')
    try {
      const options = (await getOpcionesParticipantes()).participantes
      setReassignment({ participant, options: options.filter((person) => !item?.participantes.some((p) => p.usuario_id === person.id)) })
    } catch (cause) { setEditError(cause instanceof Error ? cause.message : 'No fue posible cargar los participantes.') }
    finally { setReassigning(false) }
  }
  async function saveReassignment() {
    if (!item || !reassignment || !newMonitor || reassigning) return
    if (!await confirm({ title: 'Reasignar participación', confirmLabel: 'Reasignar',
      message: 'Se conservará la participación anterior como historial y se enviará una invitación a la nueva persona para aceptar o rechazar.' })) return
    setReassigning(true); setEditError('')
    try {
      await reassignParticipante(item.id, reassignment.participant, newMonitor)
      const saved = await getAsignacion(item.id)
      setResult({ id: item.id, item: saved, catalogos: current?.catalogos }); setReassignment(null)
      setNotice('Participación reasignada. La nueva persona recibirá una invitación.')
    } catch (cause) { setEditError(cause instanceof Error ? cause.message : 'No fue posible reasignar la participación.') }
    finally { setReassigning(false) }
  }
  async function remove() {
    if (!item || !canDelete || deleting) return
    if (!await confirm({ title: 'Eliminar asignación', confirmLabel: 'Eliminar asignación',
      message: `Se eliminará del listado la actividad del ${item.fecha.split('-').reverse().join('/')} a las ${item.hora_inicio.slice(0, 5)}. Las invitaciones quedarán invalidadas y se conservará el historial. ¿Deseas continuar?` })) return
    setDeleting(true); setEditError('')
    try {
      await deleteAsignacion(item.id)
      navigate('/app/asignaciones', { replace: true })
    } catch (cause) { setEditError(cause instanceof Error ? cause.message : 'No fue posible eliminar la asignación.') }
    finally { setDeleting(false) }
  }
  async function openEdit() {
    setOpening(true); setEditError(''); setNotice('')
    try { setOpciones(await getOpcionesEdicion()) }
    catch (cause) { setEditError(cause instanceof Error ? cause.message : 'No fue posible cargar la edición.') }
    finally { setOpening(false) }
  }
  async function saveEdit(payload: AsignacionPayload) {
    if (!item || !current?.catalogos) throw new Error('Actualiza el detalle antes de editar.')
    const changes = cambiosEdicion(payloadEdicion(item), payload)
    if (!Object.keys(changes).length) { setOpciones(null); setNotice('No hay cambios para guardar.'); return item }
    const saved = await updateAsignacion(item.id, changes)
    setResult({ id: item.id, item: saved, catalogos: current.catalogos }); setOpciones(null)
    setNotice(Object.keys(changes).some((key) => key !== 'observacion' && key !== 'contactos')
      ? 'Cambios guardados. Se solicitará reconfirmación con una nueva invitación por correo.' : 'Cambios guardados. Se conservaron las respuestas de los participantes.')
    return saved
  }
  return <section className="assignments-page">
    <header className="assignments-heading"><div><h1>Detalle de asignación</h1><p>Información registrada de la actividad.</p></div><Link className="assignments-action" to="/app/asignaciones">Volver al listado</Link></header>
    {notice && <p className="assignments-success" role="status">{notice}</p>}
    {editError && <p className="assignments-error" role="alert">{editError}</p>}
    {opciones && item ? <AsignacionCreateForm key={item.id} opciones={opciones} initial={payloadEdicion(item)} onCreate={saveEdit} onClose={() => setOpciones(null)} /> : <div className="assignments-panel">
      {!current ? <p role="status">Cargando asignación…</p> : current.error ? <div role="alert"><p className="assignments-error">{current.error}</p><button className="assignments-secondary" type="button" onClick={() => { setResult(null); setRevision((value) => value + 1) }}>Reintentar</button></div> : item && <>
        <div className="assignments-panel-heading"><h2>{tipo?.nombre ?? 'Actividad'}</h2><span className={`assignments-status assignments-status--${item.por_reasignar ? 'por_reasignar' : estado?.codigo.toLowerCase() ?? 'unknown'}`}>{item.por_reasignar ? 'Por reasignar' : estado?.nombre ?? 'Estado no disponible'}</span>
          {permissions.includes('UPDATE_ASSIGNMENT') && ['PENDIENTE','CONFIRMADA'].includes(estado?.codigo ?? '') && <button className="assignments-secondary" disabled={opening || deleting} onClick={() => void openEdit()}>{opening ? 'Cargando…' : 'Editar asignación'}</button>}
          {canDelete && <button type="button" className="assignments-delete" disabled={deleting || opening} onClick={() => void remove()}>{deleting ? 'Eliminando…' : 'Eliminar asignación'}</button>}</div>
        <dl className="assignments-detail-grid">
          <div><dt>Colegio / Lugar</dt><dd>{item.colegio_id ? colegio?.nombre ?? 'Colegio no disponible' : item.lugar ?? '—'}</dd></div>
          <div><dt>Fecha</dt><dd>{item.fecha.split('-').reverse().join('/')}</dd></div>
          <div><dt>Horario</dt><dd>{item.hora_inicio.slice(0, 5)} – {item.hora_fin.slice(0, 5)}</dd></div>
          <div><dt>Participantes registrados</dt><dd>{item.participantes.length}</dd></div>
          <div><dt>Contactos asociados</dt><dd>{item.contactos.length}</dd></div>
          <div><dt>Observación</dt><dd>{item.observacion || 'Sin observaciones'}</dd></div>
        </dl>
        {item.por_reasignar && <p className="assignments-warning">El único participante rechazó la invitación. La actividad requiere reasignación.</p>}
        <section className="assignments-form-section" aria-label="Respuestas de participantes">
          <div className="assignments-panel-heading"><h3>Participantes y respuestas</h3>
            {permissions.includes('REASSIGN_ASSIGNMENT') && ['PENDIENTE', 'CONFIRMADA'].includes(estado?.codigo ?? '') && <button type="button" className="assignments-secondary" disabled={adding || deleting} onClick={() => setAdding(true)}>Agregar participante</button>}
            <button type="button" className="assignments-secondary" onClick={() => { clearReadCache(); setRevision((value) => value + 1) }}>Actualizar respuestas</button></div>
          {adding && <AgregarParticipanteForm assignment={item.id} existing={item.participantes.map((person) => person.usuario_id)} onClose={() => setAdding(false)} onAdded={async () => {
            const saved = await getAsignacion(item.id)
            setResult({ id: item.id, item: saved, catalogos: current.catalogos })
            setNotice('Participante agregado. Recibirá una invitación para aceptar o rechazar; las respuestas anteriores se conservaron.')
          }} />}
          {!item.participantes.length ? <p>No hay participantes activos.</p> : <div className="assignments-table-scroll"><table className="assignments-table">
            <thead><tr><th>Participante</th><th>Participación</th><th>Respuesta</th><th>Fecha de respuesta</th><th>Motivo del rechazo</th><th>Acciones</th></tr></thead>
            <tbody>{item.participantes.map((participante) => <tr key={participante.id}>
              <td>{participante.usuario_nombre || 'Nombre no disponible'}</td><td>{participante.tipo_participacion_nombre || '—'}</td>
              <td><span className={`assignments-status assignments-status--${participante.estado_participacion_codigo?.toLowerCase() ?? 'unknown'}`}>{participante.estado_participacion_nombre || 'Estado no disponible'}</span></td>
              <td>{participante.fecha_respuesta ? new Date(participante.fecha_respuesta).toLocaleString('es-CL', { timeZone: 'America/Santiago' }) : 'Sin respuesta'}</td>
              <td className="assignments-response-reason">{participante.motivo_rechazo || '—'}</td>
              <td>{permissions.includes('REASSIGN_ASSIGNMENT') && ['PENDIENTE', 'CONFIRMADA'].includes(estado?.codigo ?? '') &&
                <><button type="button" className="assignments-secondary" disabled={reassigning || deleting} onClick={() => void openReassignment(participante.id)}>Cambiar participante</button>
                  <button type="button" className="assignments-delete" disabled={reassigning || deleting} onClick={() => void removePerson(participante.id, participante.usuario_nombre || 'esta persona')}>Quitar participante</button></>}</td>
            </tr>)}</tbody>
          </table></div>}
          {reassignment && <div className="assignments-form-section"><h3>Seleccionar reemplazo</h3>
            {!reassignment.options.length ? <p>No hay otras personas activas disponibles.</p> : <label>Nuevo participante<select value={newMonitor} disabled={reassigning} onChange={(event) => setNewMonitor(event.target.value)}><option value="">Selecciona una persona</option>{reassignment.options.map((person) => <option key={person.id} value={person.id}>{[person.nombres, person.apellido_paterno, person.apellido_materno].filter(Boolean).join(' ')}</option>)}</select></label>}
            <div className="assignments-editor-actions"><button type="button" className="assignments-primary" disabled={!newMonitor || reassigning} onClick={() => void saveReassignment()}>{reassigning ? 'Guardando…' : 'Reasignar participación'}</button>
              <button type="button" className="assignments-secondary" disabled={reassigning} onClick={() => setReassignment(null)}>Cancelar</button></div></div>}
        </section>
      </>}
    </div>}
    {confirmationDialog}
  </section>
}
