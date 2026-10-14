import LoadingIndicator from '../LoadingIndicator'
/**
 * HuellApp · Gestión de contactos de un colegio ya registrado.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Solo se accede después de guardar el colegio y obtener su UUID.
 * - Las acciones visibles respetan los permisos efectivos consultados por la ficha.
 * - La eliminación lógica se ofrece al final de editar y exige permiso específico.
 * - La ficha no permite salir durante una escritura de contactos.
 * - El contacto abierto y la lista se sincronizan tras modificar su estado.
 * - Cada operación es independiente y auditada por el backend.
 * - Se conserva el límite de dos contactos por asignación (en backend).
 */
import { useEffect, useState, type FormEvent } from 'react'
import {
  createContacto, deleteContacto, listContactos, setContactoActivo, updateContacto,
} from '../../services/contactosService'
import type { ContactoColegio, ContactoPayload } from '../../types/contactos'
import { useConfirmation } from '../../hooks/useConfirmation'

const EMPTY: ContactoPayload = {
  nombre: '', apellido_paterno: null, apellido_materno: null,
  rut: null, email: '', telefono: '', cargo: null,
}

interface Props {
  colegioId: string
  colegioActivo: boolean
  permissions: string[]
  onWorkingChange: (working: boolean) => void
}

/** Convierte las propiedades editables del contacto al estado del formulario. */
function toForm(contacto: ContactoColegio): ContactoPayload {
  return {
    nombre: contacto.nombre,
    apellido_paterno: contacto.apellido_paterno,
    apellido_materno: contacto.apellido_materno,
    rut: contacto.rut,
    email: contacto.email,
    telefono: contacto.telefono,
    cargo: contacto.cargo,
  }
}

/** Normaliza opcionales sin modificar los datos de auditoría ni el UUID. */
function clean(values: ContactoPayload): ContactoPayload {
  return {
    nombre: values.nombre.trim(),
    apellido_paterno: values.apellido_paterno?.trim() || null,
    apellido_materno: values.apellido_materno?.trim() || null,
    rut: values.rut?.trim() || null,
    email: values.email.trim(),
    telefono: values.telefono.trim(),
    cargo: values.cargo?.trim() || null,
  }
}

/** Gestiona el listado y un único formulario reutilizado para alta y edición. */
export default function ColegioContactos({ colegioId, colegioActivo, permissions, onWorkingChange }: Props) {
  const { confirm, confirmationDialog } = useConfirmation()
  const [items, setItems] = useState<ContactoColegio[]>([])
  const [selected, setSelected] = useState<ContactoColegio | null>(null)
  const [form, setForm] = useState<ContactoPayload>({ ...EMPTY })
  const [showForm, setShowForm] = useState(false)
  const [loading, setLoading] = useState(true)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [revision, setRevision] = useState(0)
  const canCreate = colegioActivo && permissions.includes('CREATE_SCHOOL_CONTACT')
  const canEdit = colegioActivo && permissions.includes('UPDATE_SCHOOL_CONTACT')
  const canToggle = permissions.includes('UPDATE_SCHOOL_CONTACT')
  const canDelete = permissions.includes('DELETE_SCHOOL_CONTACT')

  /** Recupera incluso los contactos inactivos para permitir su reactivación. */
  useEffect(() => {
    let active = true
    void listContactos(colegioId, true)
      .then((data) => { if (active) { setItems(data); setLoadError(null) } })
      .catch((err: unknown) => { if (active) setLoadError(err instanceof Error ? err.message : 'No se pudieron cargar los contactos.') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [colegioId, revision])

  /** Abre un formulario limpio para un nuevo contacto. */
  const newContact = () => {
    setSelected(null)
    setForm({ ...EMPTY })
    setShowForm(true)
    setError(null)
    setMessage(null)
  }

  /** Prepara la edición sin alterar la referencia del contacto existente. */
  const editContact = (item: ContactoColegio) => {
    setSelected(item)
    setForm(toForm(item))
    setShowForm(true)
    setError(null)
    setMessage(null)
  }

  const change = (field: keyof ContactoPayload, value: string) => {
    setForm((current) => ({ ...current, [field]: value }))
    setError(null)
  }

  /** Crea o modifica; PATCH envía solo diferencias reales. */
  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (working || (selected ? !canEdit : !canCreate)) return
    const payload = clean(form)
    if (!payload.nombre || !payload.email || !payload.telefono) {
      setError('Nombre, correo y teléfono son obligatorios.')
      return
    }
    const previous = selected ? toForm(selected) : null
    const changes = previous
      ? Object.fromEntries((Object.keys(payload) as Array<keyof ContactoPayload>)
          .filter((key) => payload[key] !== previous[key])
          .map((key) => [key, payload[key]])) as Partial<ContactoPayload>
      : null
    if (selected && !Object.keys(changes ?? {}).length) {
      setMessage('No hay cambios pendientes.')
      return
    }
    setWorking(true)
    onWorkingChange(true)
    setError(null)
    setMessage(null)
    try {
      const updated = selected
        ? await updateContacto(colegioId, selected.id, changes ?? {})
        : await createContacto(colegioId, payload)
      setItems((current) => selected
        ? current.map((item) => item.id === updated.id ? updated : item)
        : [...current, updated])
      setShowForm(false)
      setSelected(null)
      setMessage(selected ? 'Contacto actualizado correctamente.' : 'Contacto agregado correctamente.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No fue posible guardar el contacto.')
    } finally {
      setWorking(false)
      onWorkingChange(false)
    }
  }

  /**
   * Solicita confirmación y aplica el cambio reversible de estado.
   * Sincroniza tanto el listado como el contacto seleccionado usando la
   * respuesta del servidor; de lo contrario el botón mostraría el estado
   * anterior hasta cerrar y reabrir el formulario.
   */
  const toggle = async (item: ContactoColegio) => {
    if (working || !canToggle || (!item.activo && !colegioActivo)) return
    const action = item.activo ? 'desactivar' : 'reactivar'
    if (!await confirm({ title: `¿${item.activo ? 'Desactivar' : 'Reactivar'} contacto?`,
      message: <>Vas a {action} a <strong>{item.nombre}</strong>. Este cambio es reversible y conserva las relaciones históricas.</>,
      confirmLabel: `Sí, ${action} contacto` })) return
    setWorking(true)
    onWorkingChange(true)
    setError(null)
    setMessage(null)
    try {
      const updated = await setContactoActivo(colegioId, item.id, !item.activo)
      setItems((current) => current.map((entry) => entry.id === updated.id ? updated : entry))
      setSelected((current) => current?.id === updated.id ? updated : current)
      setMessage('Estado del contacto actualizado correctamente.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo cambiar el estado.')
    } finally {
      setWorking(false)
      onWorkingChange(false)
    }
  }

  /** Elimina solo tras doble intención: editar y confirmar expresamente. */
  const remove = async (item: ContactoColegio) => {
    if (working || !canDelete) return
    if (!await confirm({ title: '¿Eliminar contacto?',
      message: <>Vas a eliminar a <strong>{item.nombre}</strong>. No aparecerá en nuevas asignaciones. El historial se conservará y quedará registro en auditoría.</>,
      confirmLabel: 'Sí, eliminar contacto' })) return
    setWorking(true)
    onWorkingChange(true)
    setError(null)
    setMessage(null)
    try {
      await deleteContacto(colegioId, item.id)
      setItems((current) => current.filter((entry) => entry.id !== item.id))
      setShowForm(false)
      setSelected(null)
      setMessage('Contacto eliminado lógicamente. Se conservó su historial.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo eliminar el contacto.')
    } finally {
      setWorking(false)
      onWorkingChange(false)
    }
  }

  return (
    <section className="schools-form-section schools-contacts">
      {confirmationDialog}
      <div className="schools-contacts-heading">
        <div>
          <h3>Personas de contacto</h3>
          <p>Estos contactos estarán disponibles para las asignaciones del colegio.</p>
        </div>
        {!showForm && canCreate && <button type="button" className="schools-secondary" disabled={working || loading || !!loadError} onClick={newContact}>+ Agregar contacto</button>}
      </div>
      {error && <p className="schools-error" role="alert">{error}</p>}
      {message && <p className="schools-success" role="status">{message}</p>}
      {loadError && <div role="alert"><p className="schools-error">{loadError}</p><button className="schools-secondary" type="button" disabled={loading} onClick={() => { setLoading(true); setRevision((value) => value + 1) }}>Reintentar</button></div>}
      {loading ? <LoadingIndicator /> : !loadError && (
        <div className="schools-contact-list">
          {items.length === 0 && !showForm && <p className="schools-feedback">Aún no hay contactos asociados a este colegio.</p>}
          {items.map((item) => (
            <div key={item.id} className="schools-contact-row">
              <div>
                <strong>{[item.nombre, item.apellido_paterno, item.apellido_materno].filter(Boolean).join(' ')}</strong>
                <span className={`schools-status ${item.activo ? 'schools-status--active' : 'schools-status--inactive'}`}>{item.activo ? 'Activo' : 'Inactivo'}</span>
                <p>{item.cargo || 'Sin cargo'} · {item.email} · {item.telefono}</p>
              </div>
              <button type="button" className="schools-action" disabled={working} onClick={() => editContact(item)}>{canEdit ? 'Editar' : 'Ver'}</button>
            </div>
          ))}
        </div>
      )}
      {showForm && (
        <form className="schools-contact-editor" onSubmit={(event) => { void save(event) }}>
          <h4>{selected ? 'Editar contacto' : 'Nuevo contacto'}</h4>
          <fieldset className="schools-fieldset" disabled={working || (selected ? !canEdit : !canCreate)}>
            <div className="schools-form-grid">
              <label>Nombre *<input required maxLength={160} value={form.nombre} onChange={(e) => change('nombre', e.target.value)} /></label>
              <label>Apellido paterno<input maxLength={120} value={form.apellido_paterno ?? ''} onChange={(e) => change('apellido_paterno', e.target.value)} /></label>
              <label>Apellido materno<input maxLength={120} value={form.apellido_materno ?? ''} onChange={(e) => change('apellido_materno', e.target.value)} /></label>
              <label>RUT (opcional)<input placeholder="12345678-5" value={form.rut ?? ''} onChange={(e) => change('rut', e.target.value)} /></label>
              <label>Correo electrónico *<input type="email" required value={form.email} onChange={(e) => change('email', e.target.value)} /></label>
              <label>Teléfono *<input type="tel" required value={form.telefono} onChange={(e) => change('telefono', e.target.value)} /></label>
              <label className="schools-field-wide">Cargo<input maxLength={160} value={form.cargo ?? ''} onChange={(e) => change('cargo', e.target.value)} /></label>
            </div>
          </fieldset>
          <div className="schools-editor-actions">
            {(selected ? canEdit : canCreate) && <button className="schools-primary" type="submit" disabled={working}>{working ? 'Guardando...' : selected ? 'Guardar cambios' : 'Guardar contacto'}</button>}
            <button className="schools-secondary" type="button" disabled={working} onClick={() => { setShowForm(false); setSelected(null); setError(null) }}>Cancelar</button>
          </div>
          {selected && <div className="schools-contacts-admin">
            <h4>Administrar contacto</h4>
            <p>La desactivación es reversible y conserva las asignaciones históricas.</p>
            {canToggle && (selected.activo || colegioActivo) && <button type="button" className="schools-secondary" disabled={working} onClick={() => { void toggle(selected) }}>{selected.activo ? 'Desactivar contacto' : 'Reactivar contacto'}</button>}
            {canDelete && <div className="schools-contacts-delete">
              <p>La eliminación lógica no se puede deshacer desde esta interfaz.</p>
              <button type="button" className="schools-danger" disabled={working} onClick={() => { void remove(selected) }}>Eliminar contacto</button>
            </div>}
          </div>}
        </form>
      )}
    </section>
  )
}
