/**
 * HuellApp · Resumen persistido de una asignación de gestión.
 * Consulta el detalle real y conserva el diseño del listado, sin datos de demostración.
 * La edición respeta permisos y solicita reconfirmación sin alterar asistencia histórica.
 */
import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { getAsignacion, getCatalogosAsignaciones, getOpcionesEdicion, updateAsignacion } from '../services/asignacionesService'
import { getPermissions } from '../services/recursosService'
import AsignacionCreateForm from '../components/asignaciones/AsignacionCreateForm'
import { payloadEdicion, cambiosEdicion } from '../components/asignaciones/asignacionEdicion'
import type { AsignacionDetail, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion } from '../types/asignaciones'
import '../styles/asignaciones.css'

export default function AsignacionDetallePage() {
  const { asignacionId = '' } = useParams()
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
        <div className="assignments-panel-heading"><h2>{tipo?.nombre ?? 'Actividad'}</h2><span className={`assignments-status assignments-status--${estado?.codigo.toLowerCase() ?? 'unknown'}`}>{estado?.nombre ?? 'Estado no disponible'}</span>
          {permissions.includes('UPDATE_ASSIGNMENT') && ['PENDIENTE','CONFIRMADA'].includes(estado?.codigo ?? '') && <button className="assignments-secondary" disabled={opening} onClick={() => void openEdit()}>{opening ? 'Cargando…' : 'Editar asignación'}</button>}</div>
        <dl className="assignments-detail-grid">
          <div><dt>Colegio / Lugar</dt><dd>{item.colegio_id ? colegio?.nombre ?? 'Colegio no disponible' : item.lugar ?? '—'}</dd></div>
          <div><dt>Fecha</dt><dd>{item.fecha.split('-').reverse().join('/')}</dd></div>
          <div><dt>Horario</dt><dd>{item.hora_inicio.slice(0, 5)} – {item.hora_fin.slice(0, 5)}</dd></div>
          <div><dt>Participantes registrados</dt><dd>{item.participantes.length}</dd></div>
          <div><dt>Contactos asociados</dt><dd>{item.contactos.length}</dd></div>
          <div><dt>Observación</dt><dd>{item.observacion || 'Sin observaciones'}</dd></div>
        </dl>
      </>}
    </div>}
  </section>
}
