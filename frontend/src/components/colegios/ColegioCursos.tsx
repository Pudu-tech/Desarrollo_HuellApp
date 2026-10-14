import LoadingIndicator from '../LoadingIndicator'
/**
 * HuellApp · Administración de cursos de un establecimiento.
 * Lista, crea, edita y cambia estado usando los contratos existentes.
 * El colegio se obtiene de la ficha y el nombre mostrado lo genera PostgreSQL.
 * Los niveles se consultan desde el catálogo real; no se fijan listas locales.
 */
import { useEffect, useState, type FormEvent } from 'react'
import { createCurso, deleteCurso, getNivelesCurso, listCursos, setCursoActivo, updateCurso } from '../../services/cursosService'
import type { CursoItem, CursoPayload, NivelCursoItem } from '../../types/recursos'
import { useRecursosColegio } from '../../hooks/useRecursosColegio'
import RecursoEstado from './RecursoEstado'

interface Props {
  colegioId: string
  colegioActivo: boolean
  permissions: string[]
  onWorkingChange: (working: boolean) => void
}

/** Copia exclusivamente los campos editables; conserva la identidad histórica. */
const toForm = (item: CursoItem): CursoPayload => ({ nivel_curso_id: item.nivel_curso_id, seccion: item.seccion, anio: item.anio })
const emptyForm = (): CursoPayload => ({ nivel_curso_id: '', seccion: '', anio: new Date().getFullYear() })

export default function ColegioCursos({ colegioId, colegioActivo, permissions, onWorkingChange }: Props) {
  const state = useRecursosColegio(colegioId, listCursos, onWorkingChange)
  const [selected, setSelected] = useState<CursoItem | null>(null)
  const [form, setForm] = useState<CursoPayload>(emptyForm)
  const [showForm, setShowForm] = useState(false)
  const [niveles, setNiveles] = useState<NivelCursoItem[]>([])
  const [nivelesError, setNivelesError] = useState('')
  const [nivelesLoading, setNivelesLoading] = useState(true)
  const [catalogRevision, setCatalogRevision] = useState(0)
  const canCreate = colegioActivo && permissions.includes('CREATE_COURSE')
  const canEdit = colegioActivo && permissions.includes('UPDATE_COURSE')
  const canActivate = colegioActivo && permissions.includes('ACTIVATE_COURSE')
  const canDeactivate = permissions.includes('DEACTIVATE_COURSE')
  const canDelete = permissions.includes('DELETE_COURSE')

  useEffect(() => {
    let active = true
    void getNivelesCurso()
      .then((data) => { if (active) { setNiveles(data); setNivelesError('') } })
      .catch((cause: unknown) => { if (active) setNivelesError(cause instanceof Error ? cause.message : 'No se pudieron cargar los niveles.') })
      .finally(() => { if (active) setNivelesLoading(false) })
    return () => { active = false }
  }, [catalogRevision])

  function open(item: CursoItem | null) {
    setSelected(item)
    setForm(item ? toForm(item) : emptyForm())
    setShowForm(true)
    state.clearFeedback()
  }

  /* ============================================================
     CREACIÓN Y EDICIÓN AUDITADAS
     ============================================================ */
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (state.working || (selected ? !canEdit : !canCreate)) return
    const payload = { ...form, seccion: form.seccion.trim().toUpperCase() }
    if (!niveles.some((item) => item.id === payload.nivel_curso_id) || !/^[A-Z]$/.test(payload.seccion)
      || !Number.isInteger(payload.anio) || payload.anio < 2000 || payload.anio > 2100) {
      state.setError('Selecciona un nivel activo, una sección de A a Z y un año entre 2000 y 2100.')
      return
    }
    const changes = selected ? Object.fromEntries(
      (Object.keys(payload) as Array<keyof CursoPayload>).filter((key) => payload[key] !== selected[key]).map((key) => [key, payload[key]]),
    ) as Partial<CursoPayload> : null
    if (selected && !Object.keys(changes ?? {}).length) { state.setError('No hay cambios pendientes.'); return }
    await state.run(
      () => selected ? updateCurso(selected.id, changes ?? {}) : createCurso(colegioId, payload),
      selected ? 'Curso actualizado correctamente.' : 'Curso creado correctamente.',
      (updated) => {
        state.setItems((items) => selected ? items.map((item) => item.id === updated.id ? updated : item) : [...items, updated])
        if (selected) {
          setSelected(updated)
          setForm(toForm(updated))
        } else {
          setSelected(null)
          setForm(emptyForm())
          setShowForm(false)
        }
      },
    )
  }

  async function toggle(item: CursoItem) {
    if (item.activo ? !canDeactivate : !canActivate) return
    await state.run(() => setCursoActivo(item.id, !item.activo), 'Estado del curso actualizado.', (updated) => {
      state.setItems((items) => items.map((entry) => entry.id === updated.id ? updated : entry))
      setSelected(updated)
    })
  }

  async function remove(item: CursoItem) {
    if (!canDelete) return
    await state.run(() => deleteCurso(item.id), 'Curso eliminado. El historial se conservó.', () => {
      state.setItems((items) => items.filter((entry) => entry.id !== item.id))
      setSelected(null)
      setShowForm(false)
    })
  }

  return <section className="schools-form-section">
    <div className="schools-contacts-heading"><div><h3>Cursos</h3><p>Niveles, secciones y años académicos de este colegio.</p></div>
      {!showForm && canCreate && <button type="button" className="schools-secondary" disabled={state.loading || state.working || !!state.loadError} onClick={() => open(null)}>+ Crear curso</button>}
    </div>
    {(state.error || state.loadError) && <p className="schools-error" role="alert">{state.error || state.loadError}</p>}
    {state.message && <p className="schools-success" role="status">{state.message}</p>}
    {state.loadError && <button className="schools-secondary" type="button" disabled={state.loading} onClick={state.refresh}>Reintentar</button>}
    {state.loading ? <LoadingIndicator /> : !state.loadError && <div className="schools-table-scroll">
      <table className="schools-table"><thead><tr><th scope="col">Curso</th><th scope="col">Año</th><th scope="col">Estado</th><th scope="col">Acciones</th></tr></thead>
        <tbody>{state.items.map((item) => <tr key={item.id}>
          <td>{item.nombre_mostrado}</td><td>{item.anio}</td><td><span className={`schools-status schools-status--${item.activo ? 'active' : 'inactive'}`}>{item.activo ? 'Activo' : 'Inactivo'}</span></td>
          <td><button type="button" className="schools-action" disabled={state.working} onClick={() => open(item)}>{canEdit ? 'Editar' : 'Ver'}</button></td>
        </tr>)}</tbody>
      </table>{!state.items.length && <p className="schools-feedback">Aún no hay cursos registrados.</p>}
    </div>}
    {showForm && <form className="schools-resource-editor" onSubmit={(event) => void save(event)}>
      <h4>{selected ? `Curso: ${selected.nombre_mostrado}` : 'Nuevo curso'}</h4>
      <p>El nombre mostrado se genera al guardar el nivel y la sección.</p>
      {nivelesError && <div role="alert"><p className="schools-error">{nivelesError}</p><button type="button" className="schools-secondary" onClick={() => { setNivelesLoading(true); setCatalogRevision((value) => value + 1) }}>Reintentar niveles</button></div>}
      <fieldset className="schools-fieldset" disabled={state.working || nivelesLoading || !!nivelesError || (selected ? !canEdit : !canCreate)}>
        <div className="schools-form-grid">
          <label>Nivel<select required value={form.nivel_curso_id} onChange={(event) => setForm((previous) => ({ ...previous, nivel_curso_id: event.target.value }))}>
            <option value="">{nivelesLoading ? 'Cargando niveles…' : 'Seleccionar nivel'}</option>
            {selected && !niveles.some((item) => item.id === selected.nivel_curso_id) && <option value={selected.nivel_curso_id}>Nivel actual no disponible para nuevas operaciones</option>}
            {niveles.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}
          </select></label>
          <label>Sección<input required maxLength={1} pattern="[A-Za-z]" value={form.seccion} onChange={(event) => setForm((previous) => ({ ...previous, seccion: event.target.value.toUpperCase() }))} /></label>
          <label>Año<input type="number" required min={2000} max={2100} step={1} value={Number.isNaN(form.anio) ? '' : form.anio} onChange={(event) => setForm((previous) => ({ ...previous, anio: event.target.valueAsNumber }))} /></label>
        </div>
      </fieldset>
      <div className="schools-editor-actions">
        {(selected ? canEdit : canCreate) && <button type="submit" className="schools-primary" disabled={state.working || nivelesLoading || !!nivelesError}>{state.working ? 'Procesando…' : 'Guardar curso'}</button>}
        <button type="button" className="schools-secondary" disabled={state.working} onClick={() => { setShowForm(false); setSelected(null); state.clearFeedback() }}>Cerrar</button>
      </div>
      {selected && <RecursoEstado nombre={selected.nombre_mostrado} activo={selected.activo} working={state.working}
        canToggle={selected.activo ? canDeactivate : canActivate} canDelete={canDelete}
        onToggle={() => void toggle(selected)} onDelete={() => void remove(selected)} />}
    </form>}
  </section>
}
