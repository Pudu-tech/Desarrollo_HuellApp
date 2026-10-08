import { clearReadCache } from '../services/readCache'
/** HuellApp · Mantenedor transversal de asignaturas y sus espacios.
 * Respeta permisos efectivos, confirmaciones comunes e historial de asignaciones.
 */
import { useEffect, useState } from 'react'
import RecursoAcademicoForm from '../components/catalogoAcademico/RecursoAcademicoForm'
import { useConfirmation } from '../hooks/useConfirmation'
import { getPermissions } from '../services/recursosService'
import { createRecursoAcademico, deleteRecursoAcademico, getCatalogoAcademico, setRecursoAcademicoActivo, updateRecursoAcademico } from '../services/catalogoAcademicoService'
import type { CatalogoAcademico, DatosAcademicos, EntidadAcademica, RecursoAcademico } from '../types/catalogoAcademico'
import '../styles/asignaciones.css'
import '../styles/catalogo-academico.css'

const tabs: Array<{ key: EntidadAcademica; label: string }> = [
  { key: 'asignaturas', label: 'Asignaturas' }, { key: 'reflexion', label: 'Espacios de reflexión' }, { key: 'encuentro', label: 'Espacios de encuentro' },
]
const messageOf = (cause: unknown) => cause instanceof Error ? cause.message : 'No fue posible completar la operación.'

export default function CatalogoAcademicoPage() {
  const [data, setData] = useState<CatalogoAcademico | null>(null)
  const [permissions, setPermissions] = useState<string[]>([])
  const [tab, setTab] = useState<EntidadAcademica>('asignaturas')
  const [subjectId, setSubjectId] = useState('')
  const [search, setSearch] = useState('')
  const [state, setState] = useState('')
  const [editor, setEditor] = useState<{ recurso: RecursoAcademico | null } | null>(null)
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const { confirm, confirmationDialog } = useConfirmation()
  const can = (action: string) => permissions.includes(`${action}_ACADEMIC_CATALOG`)
  const subject = data?.asignaturas.find((item) => item.id === subjectId) ?? null
  const isSubject = tab === 'asignaturas'

  useEffect(() => {
    let active = true
    void Promise.all([getPermissions(), getCatalogoAcademico()]).then(([rights, catalog]) => {
      if (!active) return
      setPermissions(rights); setData(catalog); setError(''); setLoading(false)
    }).catch((cause) => { if (active) { setPermissions([]); setData(null); setError(messageOf(cause)); setLoading(false) } })
    return () => { active = false }
  }, [revision])

  /** Refresca también las cascadas: no deja espacios eliminados en otro tab. */
  async function reloadAfterWrite() {
    try { setData(await getCatalogoAcademico()) }
    catch (cause) { setData(null); setError(`El cambio se guardó. ${messageOf(cause)} Usa Actualizar para volver a cargar.`) }
  }
  async function save(datos: DatosAcademicos) {
    setBusy(true)
    try {
      if (editor?.recurso) await updateRecursoAcademico(tab, editor.recurso.id, datos)
      else await createRecursoAcademico(tab, datos)
      setEditor(null); setNotice('Recurso guardado y registrado en auditoría.'); setError('')
      await reloadAfterWrite()
    } finally { setBusy(false) }
  }

  async function change(item: RecursoAcademico, remove = false) {
    if (busy) return
    const action = remove ? 'Eliminar' : item.activo ? 'Desactivar' : 'Activar'
    if (!await confirm({ title: `¿${action} ${isSubject ? 'asignatura' : 'espacio'}?`, confirmLabel: `Sí, ${action.toLowerCase()}`,
      message: <>{action} <strong>{item.nombre}</strong>. {remove && isSubject ? 'También se eliminarán lógicamente sus espacios. ' : ''}
        {remove ? 'Se conservará el historial de asignaciones. La acción no se puede deshacer desde la interfaz.' : 'El cambio de estado es reversible.'} Quedará registro en auditoría.</> })) return
    setBusy(true); setError(''); setNotice('')
    try {
      if (remove) await deleteRecursoAcademico(tab, item.id)
      else await setRecursoAcademicoActivo(tab, item.id, !item.activo)
      setNotice('Cambio guardado y registrado en auditoría.')
      await reloadAfterWrite()
    } catch (cause) { setError(messageOf(cause)) }
    finally { setBusy(false) }
  }

  const items = (data?.[tab] ?? []).filter((item) =>
    (isSubject || item.ramo_id === subjectId) && (!state || String(item.activo) === state)
    && item.nombre.toLocaleLowerCase('es-CL').includes(search.trim().toLocaleLowerCase('es-CL')))
  const ready = !busy && !loading && !!data
  return <section className="assignments-page academic-page">
    <header className="assignments-heading"><div><h1>Catálogo académico</h1><p>Asignaturas y espacios compartidos por todos los colegios.</p></div>
      {can('CREATE') && !editor && <button className="assignments-primary" disabled={!ready || (!isSubject && !subject?.activo)} onClick={() => { setEditor({ recurso: null }); setNotice('') }}>+ Crear {isSubject ? 'asignatura' : 'espacio'}</button>}
    </header>
    {error && <p className="assignments-error" role="alert">{error}</p>}
    {notice && <p className="assignments-success" role="status">{notice}</p>}
    <nav className="academic-tabs" aria-label="Secciones del catálogo">{tabs.map((item) => <button key={item.key} aria-current={tab === item.key ? 'page' : undefined} disabled={busy || !!editor} onClick={() => { setTab(item.key); setSearch(''); setState(''); setNotice('') }}>{item.label}</button>)}</nav>
    {editor && data ? <RecursoAcademicoForm entidad={tab} recurso={editor.recurso} asignatura={subject} niveles={data.niveles} onSave={save} onCancel={() => setEditor(null)} /> : <div className="assignments-panel">
      <div className="assignments-panel-heading"><div><h2>{tabs.find((item) => item.key === tab)?.label}</h2><p>{loading ? 'Cargando…' : `${items.length} recursos`}</p></div>
        <button className="assignments-secondary" disabled={busy || loading} onClick={() => { clearReadCache(); setLoading(true); setRevision((value) => value + 1) }}>Actualizar</button></div>
      <div className="assignments-filters">
        {!isSubject && <label>Asignatura<select value={subjectId} disabled={!ready} onChange={(event) => setSubjectId(event.target.value)}><option value="">Seleccionar asignatura</option>{data?.asignaturas.map((item) => <option key={item.id} value={item.id}>{item.nombre}{!item.activo ? ' (inactiva)' : ''}</option>)}</select></label>}
        <label>Buscar<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Nombre" /></label>
        <label>Estado<select value={state} onChange={(event) => setState(event.target.value)}><option value="">Todos</option><option value="true">Activo</option><option value="false">Inactivo</option></select></label>
      </div>
      {loading ? <p className="assignments-feedback">Cargando catálogo…</p> : !data ? <p className="assignments-feedback">El catálogo no está disponible.</p>
        : !isSubject && !subject ? <p className="assignments-feedback">Selecciona una asignatura para administrar sus espacios.</p>
        : !items.length ? <p className="assignments-feedback">No hay recursos para los filtros seleccionados.</p>
        : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th>Nombre</th><th>{isSubject ? 'Niveles' : 'Orden'}</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>
          {items.map((item) => <tr key={item.id}><td><span className="assignments-name">{item.nombre}</span>{item.descripcion && <p className="academic-item-description">{item.descripcion}</p>}</td>
            <td>{isSubject ? item.nivel_ids.map((id) => data.niveles.find((nivel) => nivel.id === id)?.nombre ?? 'Nivel histórico').join(', ') : item.orden ?? '—'}</td>
            <td><span className={`assignments-status ${item.activo ? 'assignments-status--confirmada' : ''}`}>{item.activo ? 'Activo' : 'Inactivo'}</span></td>
            <td><div className="academic-actions">
              {can('UPDATE') && <button className="assignments-secondary" disabled={!ready || (!isSubject && !subject?.activo)} onClick={() => setEditor({ recurso: item })}>Editar</button>}
              {can(item.activo ? 'DEACTIVATE' : 'ACTIVATE') && <button className="assignments-secondary" disabled={!ready || (!isSubject && !item.activo && !subject?.activo)} onClick={() => void change(item)}>{item.activo ? 'Desactivar' : 'Activar'}</button>}
              {can('DELETE') && <button className="assignments-secondary academic-danger" disabled={!ready} onClick={() => void change(item, true)}>Eliminar</button>}
              {!can('UPDATE') && !can(item.activo ? 'DEACTIVATE' : 'ACTIVATE') && !can('DELETE') && <span>Solo consulta</span>}
            </div></td></tr>)}
        </tbody></table></div>}
    </div>}
    {confirmationDialog}
  </section>
}
