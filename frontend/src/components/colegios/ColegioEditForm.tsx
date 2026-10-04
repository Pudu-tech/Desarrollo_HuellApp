/**
 * HuellAPP · Formulario de edición de colegios.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Conserva la edición separada de la activación/desactivación.
 * - La comuna seleccionada debe pertenecer a la región actual.
 * - PATCH envía solo campos modificados; los opcionales vacíos pasan a null.
 * - El backend realiza la validación y auditoría definitivas.
 */

import { useEffect, useState, type FormEvent } from 'react'
import { getComunas } from '../../services/colegiosService'
import ColegioFields from './ColegioFields'
import ColegioContactos from './ColegioContactos'
import { colegioToForm, normalizeColegio, validateColegio, type ColegioFormValues } from './colegioForm'
import type { ColegioListItem, ComunaItem, RegionItem, TipoDependenciaItem } from '../../types/colegios'

/**
 * Contrato del componente: operaciones recibidas desde la página contenedora.
 */
interface Props {
  colegio: ColegioListItem
  regiones: RegionItem[]
  dependencias: TipoDependenciaItem[]
  onSave: (id: string, changes: Partial<Omit<ColegioListItem, 'id' | 'activo'>>) => Promise<ColegioListItem>
  onToggleStatus: (colegio: ColegioListItem) => Promise<ColegioListItem>
  onClose: () => void
  /** El backend aplica permisos: la interfaz también oculta eliminación por rol. */
  canDeleteContactos: boolean
  /** Solicita al contenedor la confirmación de eliminación (solo SUPERADMIN). */
  onRequestDelete?: (colegio: ColegioListItem) => void
}


/**
 * Administra el formulario, la carga de comunas y los mensajes de operación.
 */
function ColegioEditForm({ colegio, regiones, dependencias, onSave, onToggleStatus, onClose, onRequestDelete, canDeleteContactos }: Props) {
  const [current, setCurrent] = useState(colegio)
  const [form, setForm] = useState<ColegioFormValues>(() => colegioToForm(colegio))
  const [comunas, setComunas] = useState<ComunaItem[]>([])
  const [loadingComunas, setLoadingComunas] = useState(false)
  const [comunasError, setComunasError] = useState<string | null>(null)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  // Evita que una respuesta tardía de otra región sobrescriba las comunas vigentes.
  useEffect(() => {
    if (!form.region_id) {
      setComunas([])
      setLoadingComunas(false)
      setComunasError(null)
      return
    }
    let active = true
    setLoadingComunas(true)
    setComunasError(null)
    setComunas([])
    void getComunas(form.region_id)
      .then((items) => { if (active) setComunas(items) })
      .catch(() => { if (active) setComunasError('No se pudieron cargar las comunas. Intenta seleccionar nuevamente la región.') })
      .finally(() => { if (active) setLoadingComunas(false) })
    return () => { active = false }
  }, [form.region_id])

  const change = <K extends keyof ColegioFormValues>(key: K, value: ColegioFormValues[K]) => {
    setForm((previous) => ({ ...previous, [key]: value }))
    setError(null)
    setSuccess(null)
  }

/**
 * Valida los campos requeridos y envía solo diferencias mediante PATCH.
 * @param event Envío del formulario; se evita la navegación del navegador.
 */
  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (working) return
    setError(null)
    setSuccess(null)
    const validationError = validateColegio(form, comunas)
    if (validationError || loadingComunas || comunasError) {
      setError(validationError ?? 'Espera a que terminen de cargar las comunas.')
      return
    }
    // PATCH mantiene el contrato previo: envía únicamente campos distintos.
    const original = colegioToForm(current)
    const normalized = normalizeColegio(form)
    const changes = Object.fromEntries(
      (Object.keys(normalized) as Array<keyof ColegioFormValues>)
        .filter((key) => normalized[key] !== original[key])
        .map((key) => [key, normalized[key]]),
    ) as Partial<ColegioFormValues>
    if (!Object.keys(changes).length) {
      setSuccess('No hay cambios pendientes.')
      return
    }
    setWorking(true)
    try {
      const updated = await onSave(current.id, changes)
      setCurrent(updated)
      setForm(colegioToForm(updated))
      setSuccess('Colegio actualizado correctamente.')
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'No se pudo guardar el colegio.')
    } finally {
      setWorking(false)
    }
  }

/**
 * Solicita confirmación antes de desactivar o reactivar el establecimiento.
 * No elimina datos ni modifica sus relaciones históricas.
 */
  const toggle = async () => {
    if (working) return
    const action = current.activo ? 'desactivar' : 'reactivar'
    if (!window.confirm(`¿Confirmas que deseas ${action} el colegio «${current.nombre}»?`)) return
    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      const updated = await onToggleStatus(current)
      setCurrent(updated)
      setForm(colegioToForm(updated))
      setSuccess(updated.activo ? 'Colegio reactivado correctamente.' : 'Colegio desactivado correctamente.')
    } catch (toggleError) {
      setError(toggleError instanceof Error ? toggleError.message : 'No fue posible cambiar el estado.')
    } finally {
      setWorking(false)
    }
  }

  return (
    <div className="schools-editor">
      <div className="schools-editor-heading">
        <div><h2>Editar colegio</h2><p>{current.nombre}</p></div>
        <button className="schools-secondary" type="button" onClick={onClose} disabled={working}>Volver al listado</button>
      </div>
      {error && <p className="schools-error" role="alert">{error}</p>}
      {success && <p className="schools-success" role="status">{success}</p>}
      <form onSubmit={(event) => { void save(event) }}>
        <fieldset disabled={working} className="schools-fieldset">
          <ColegioFields
            values={form}
            regiones={regiones}
            comunas={comunas}
            dependencias={dependencias}
            loadingComunas={loadingComunas}
            comunasError={comunasError}
            change={change}
            onRegionChange={(nextRegion) => {
              setForm((prev) => ({ ...prev, region_id: nextRegion, comuna_id: '' }))
              setError(null)
              setSuccess(null)
            }}
          />
          {comunasError && <p className="schools-error" role="alert">{comunasError}</p>}
        </fieldset>
        <div className="schools-editor-actions">
          <button className="schools-primary" type="submit" disabled={working || loadingComunas || !!comunasError}>{working ? 'Procesando...' : 'Guardar cambios'}</button>
          <button className="schools-secondary" type="button" onClick={onClose} disabled={working}>Cancelar</button>
        </div>
      </form>
      {Boolean(current.nombre_contacto || current.telefono_contacto || current.email_contacto) && (
        <section className="schools-form-section schools-legacy-contact">
          <h3>Contacto anterior (solo consulta)</h3>
          <p>Estos datos históricos no están vinculados con Asignaciones. Para disponer de esta persona en nuevas actividades, regístrala en la sección de contactos.</p>
          <p><strong>Nombre:</strong> {current.nombre_contacto || '—'}</p>
          <p><strong>Teléfono:</strong> {current.telefono_contacto || '—'}</p>
          <p><strong>Correo:</strong> {current.email_contacto || '—'}</p>
        </section>
      )}
      <ColegioContactos colegioId={current.id} canDelete={canDeleteContactos} />
      <section className="schools-form-section schools-status-section">
        <h3>Estado del colegio</h3>
        <p>Estado actual: <strong>{current.activo ? 'Activo' : 'Inactivo'}</strong></p>
        <p>Desactivar es reversible y conserva la información del establecimiento y su historial.</p>
        <button className={current.activo ? 'schools-danger' : 'schools-secondary'} type="button" disabled={working} onClick={() => { void toggle() }}>
          {current.activo ? 'Desactivar colegio' : 'Reactivar colegio'}
        </button>
      </section>
      {onRequestDelete && (
        <section className="schools-form-section schools-delete-section">
          <h3>Eliminar colegio</h3>
          <p>El colegio dejará de estar disponible, pero se conservarán los registros históricos y la auditoría.</p>
          <button type="button" className="schools-danger" disabled={working} onClick={() => onRequestDelete(current)}>
            Eliminar colegio
          </button>
        </section>
      )}
    </div>
  )
}

export default ColegioEditForm
