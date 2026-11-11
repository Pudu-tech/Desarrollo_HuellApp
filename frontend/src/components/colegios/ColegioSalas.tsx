/**
 * HuellApp · Salas de un colegio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Listar, ordenar y gestionar salas y sus cambios de estado.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Eliminación lógica confirmada desde la edición; conserva relaciones históricas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import SortableHeader from '../../components/common/SortableHeader'
import { useListSort } from '../../hooks/useListSort'
import LoadingIndicator from '../LoadingIndicator'

import { useState, type FormEvent } from 'react'
import { createSala, deleteSala, listSalas, setSalaActivo, updateSala } from '../../services/salasService'
import type { SalaItem, SalaPayload } from '../../types/recursos'
import { useRecursosColegio } from '../../hooks/useRecursosColegio'
import RecursoEstado from './RecursoEstado'

interface Props {
  colegioId: string
  colegioActivo: boolean
  permissions: string[]
  onWorkingChange: (working: boolean) => void
}

/** Transforma los campos editables sin aceptar colegio ni datos de auditoría. */
const toForm = (item: SalaItem): SalaPayload => ({ nombre: item.nombre, descripcion: item.descripcion, capacidad: item.capacidad, ubicacion: item.ubicacion })
const emptyForm = (): SalaPayload => ({ nombre: '', descripcion: null, capacidad: null, ubicacion: null })

export default function ColegioSalas({ colegioId, colegioActivo, permissions, onWorkingChange }: Props) {
  const state = useRecursosColegio(colegioId, listSalas, onWorkingChange)
  const sorting = useListSort<string>('nombre')
  const [selected, setSelected] = useState<SalaItem | null>(null)
  const [form, setForm] = useState<SalaPayload>(emptyForm)
  const [showForm, setShowForm] = useState(false)
  const canCreate = colegioActivo && permissions.includes('CREATE_ROOM')
  const canEdit = colegioActivo && permissions.includes('UPDATE_ROOM')
  const canActivate = colegioActivo && permissions.includes('ACTIVATE_ROOM')
  const canDeactivate = permissions.includes('DEACTIVATE_ROOM')
  const canDelete = permissions.includes('DELETE_ROOM')

  /** Prepara el formulario para crear o editar y limpia los mensajes de la operación anterior. */
  function open(item: SalaItem | null) {
    setSelected(item)
    setForm(item ? toForm(item) : emptyForm())
    setShowForm(true)
    state.clearFeedback()
  }

  /* ============================================================
     PERSISTENCIA Y ACTUALIZACIÓN INMEDIATA DE LA FICHA
     ============================================================ */
  /** Valida los campos y aplica la respuesta confirmada mediante el estado compartido del colegio. */
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (state.working || (selected ? !canEdit : !canCreate)) return
    const payload: SalaPayload = {
      ...form, nombre: form.nombre.trim(),
      descripcion: form.descripcion?.trim() || null, ubicacion: form.ubicacion?.trim() || null,
    }
    if (!payload.nombre || (payload.capacidad !== null && (!Number.isInteger(payload.capacidad) || payload.capacidad < 1 || payload.capacidad > 1000))) {
      state.setError('Indica un nombre y, si corresponde, una capacidad entera entre 1 y 1000.')
      return
    }
    const changes = selected ? Object.fromEntries(
      (Object.keys(payload) as Array<keyof SalaPayload>).filter((key) => payload[key] !== selected[key]).map((key) => [key, payload[key]]),
    ) as Partial<SalaPayload> : null
    if (selected && !Object.keys(changes ?? {}).length) { state.setError('No hay cambios pendientes.'); return }
    await state.run(
      () => selected ? updateSala(selected.id, changes ?? {}) : createSala(colegioId, payload),
      selected ? 'Sala actualizada correctamente.' : 'Sala creada correctamente.',
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

  /** Comprueba la capacidad visible y sincroniza el recurso tras cambiar su estado en la API. */
  async function toggle(item: SalaItem) {
    if (item.activo ? !canDeactivate : !canActivate) return
    await state.run(() => setSalaActivo(item.id, !item.activo), 'Estado de la sala actualizado.', (updated) => {
      state.setItems((items) => items.map((entry) => entry.id === updated.id ? updated : entry))
      setSelected(updated)
    })
  }

  /** Solicita la eliminación lógica y retira el recurso del listado después de la confirmación del backend. */
  async function remove(item: SalaItem) {
    if (!canDelete) return
    await state.run(() => deleteSala(item.id), 'Sala eliminada. El historial se conservó.', () => {
      state.setItems((items) => items.filter((entry) => entry.id !== item.id))
      setSelected(null)
      setShowForm(false)
    })
  }

  return <section className="schools-form-section">
    <div className="schools-contacts-heading"><div><h3>Salas</h3><p>Espacios disponibles en este colegio.</p></div>
      {!showForm && canCreate && <button type="button" className="schools-secondary" disabled={state.loading || state.working || !!state.loadError} onClick={() => open(null)}>+ Crear sala</button>}
    </div>
    {(state.error || state.loadError) && <p className="schools-error" role="alert">{state.error || state.loadError}</p>}
    {state.message && <p className="schools-success" role="status">{state.message}</p>}
    {state.loadError && <button className="schools-secondary" type="button" disabled={state.loading} onClick={state.refresh}>Reintentar</button>}
    {state.loading ? <LoadingIndicator /> : !state.loadError && <div className="schools-table-scroll">
      <table className="schools-table"><thead><tr><SortableHeader label="Sala" column="nombre" sort={sorting.sort} onSort={sorting.toggle} /><th scope="col">Capacidad</th><SortableHeader label="Ubicación" column="ubicacion" sort={sorting.sort} onSort={sorting.toggle} /><th scope="col">Estado</th><th scope="col">Acciones</th></tr></thead>
        <tbody>{sorting.order(state.items, { nombre: r => r.nombre, ubicacion: r => r.ubicacion }).map((item) => <tr key={item.id}>
          <td>{item.nombre}</td><td>{item.capacidad ?? '—'}</td><td>{item.ubicacion || '—'}</td><td><span className={`schools-status schools-status--${item.activo ? 'active' : 'inactive'}`}>{item.activo ? 'Activo' : 'Inactivo'}</span></td>
          <td><button type="button" className="schools-action" disabled={state.working} onClick={() => open(item)}>{canEdit ? 'Editar' : 'Ver'}</button></td>
        </tr>)}</tbody>
      </table>{!state.items.length && <p className="schools-feedback">Aún no hay salas registradas.</p>}
    </div>}
    {showForm && <form className="schools-resource-editor" onSubmit={(event) => void save(event)}>
      <h4>{selected ? `Sala: ${selected.nombre}` : 'Nueva sala'}</h4>
      <fieldset className="schools-fieldset" disabled={state.working || (selected ? !canEdit : !canCreate)}>
        <div className="schools-form-grid">
          <label>Nombre<input required maxLength={150} value={form.nombre} onChange={(event) => setForm((previous) => ({ ...previous, nombre: event.target.value }))} /></label>
          <label>Capacidad (opcional)<input type="number" min={1} max={1000} step={1} value={form.capacidad ?? ''} onChange={(event) => setForm((previous) => ({ ...previous, capacidad: event.target.value === '' ? null : event.target.valueAsNumber }))} /></label>
          <label>Ubicación (opcional)<input maxLength={200} value={form.ubicacion ?? ''} onChange={(event) => setForm((previous) => ({ ...previous, ubicacion: event.target.value }))} /></label>
          <label>Descripción (opcional)<textarea maxLength={500} value={form.descripcion ?? ''} onChange={(event) => setForm((previous) => ({ ...previous, descripcion: event.target.value }))} /></label>
        </div>
      </fieldset>
      <div className="schools-editor-actions">
        {(selected ? canEdit : canCreate) && <button type="submit" className="schools-primary" disabled={state.working}>{state.working ? 'Procesando…' : 'Guardar sala'}</button>}
        <button type="button" className="schools-secondary" disabled={state.working} onClick={() => { setShowForm(false); setSelected(null); state.clearFeedback() }}>Cerrar</button>
      </div>
      {selected && <RecursoEstado nombre={selected.nombre} activo={selected.activo} working={state.working}
        canToggle={selected.activo ? canDeactivate : canActivate} canDelete={canDelete}
        onToggle={() => void toggle(selected)} onDelete={() => void remove(selected)} />}
    </form>}
  </section>
}
