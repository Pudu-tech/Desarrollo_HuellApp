/**
 * HuellApp · Ficha de edición del colegio con cuatro secciones internas.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Conserva la edición separada de la activación/desactivación.
 * - La comuna seleccionada debe pertenecer a la región actual.
 * - PATCH envía solo campos modificados; los opcionales vacíos pasan a null.
 * - El backend realiza la validación y auditoría definitivas.
 * - Los permisos se consultan una vez; los paneles visitados conservan estado.
 * - No se permite abandonar la ficha durante una escritura de sus recursos.
 */

import { useEffect, useState, type FormEvent } from 'react'
import { getComunas } from '../../services/colegiosService'
import ColegioFields from './ColegioFields'
import ColegioContactos from './ColegioContactos'
import ColegioCursos from './ColegioCursos'
import ColegioSalas from './ColegioSalas'
import ColegioTabs, { type ColegioSection } from './ColegioTabs'
import { getPermissions } from '../../services/recursosService'
import { useConfirmation } from '../../hooks/useConfirmation'
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
  /** Solicita al contenedor la confirmación de eliminación (solo SUPERADMIN). */
  onRequestDelete?: (colegio: ColegioListItem) => void
}


/**
 * Administra el formulario, la carga de comunas y los mensajes de operación.
 */
function ColegioEditForm({ colegio, regiones, dependencias, onSave, onToggleStatus, onClose, onRequestDelete }: Props) {
  const [current, setCurrent] = useState(colegio)
  const { confirm, confirmationDialog } = useConfirmation()
  const [form, setForm] = useState<ColegioFormValues>(() => colegioToForm(colegio))
  const [comunas, setComunas] = useState<ComunaItem[]>([])
  const [loadingComunas, setLoadingComunas] = useState(true)
  const [comunasError, setComunasError] = useState<string | null>(null)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [section, setSection] = useState<ColegioSection>('informacion')
  const [visited, setVisited] = useState<ColegioSection[]>(['informacion'])
  const [permissions, setPermissions] = useState<string[]>([])
  const [permissionsError, setPermissionsError] = useState('')
  const [permissionsLoading, setPermissionsLoading] = useState(true)
  const [permissionsRevision, setPermissionsRevision] = useState(0)
  const [childWorking, setChildWorking] = useState(false)
  const busy = working || childWorking
  const canEdit = permissions.includes('UPDATE_SCHOOL')
  const canToggle = permissions.includes(current.activo ? 'DEACTIVATE_SCHOOL' : 'ACTIVATE_SCHOOL')

  useEffect(() => {
    let active = true
    void getPermissions()
      .then((items) => { if (active) { setPermissions(items); setPermissionsError('') } })
      .catch((cause: unknown) => { if (active) setPermissionsError(cause instanceof Error ? cause.message : 'No se pudieron consultar los permisos.') })
      .finally(() => { if (active) setPermissionsLoading(false) })
    return () => { active = false }
  }, [permissionsRevision])

  /** Abrir otra sección conserva los formularios y listados previamente visitados. */
  const changeSection = (next: ColegioSection) => {
    if (busy) return
    setSection(next)
    setVisited((previous) => previous.includes(next) ? previous : [...previous, next])
  }

  // Evita que una respuesta tardía de otra región sobrescriba las comunas vigentes.
  useEffect(() => {
    let active = true
    void (form.region_id ? getComunas(form.region_id) : Promise.resolve([]))
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
    if (busy || !canEdit) return
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
    if (busy || !canToggle) return
    const action = current.activo ? 'desactivar' : 'reactivar'
    if (!await confirm({ title: `¿${current.activo ? 'Desactivar' : 'Reactivar'} colegio?`,
      message: <>Vas a {action} <strong>{current.nombre}</strong>. Este cambio es reversible y conserva la información y el historial.</>,
      confirmLabel: `Sí, ${action} colegio` })) return
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
      {confirmationDialog}
      <div className="schools-editor-heading">
        <div><h2>{current.nombre}</h2><p>Ficha del establecimiento · <span className={`schools-status schools-status--${current.activo ? 'active' : 'inactive'}`}>{current.activo ? 'Activo' : 'Inactivo'}</span></p></div>
        <button className="schools-secondary" type="button" onClick={onClose} disabled={busy}>Volver al listado</button>
      </div>
      {permissionsLoading && <p role="status">Cargando permisos de administración…</p>}
      {permissionsError && <div role="alert"><p className="schools-error">{permissionsError}</p><button type="button" className="schools-secondary" disabled={permissionsLoading} onClick={() => { setPermissionsLoading(true); setPermissionsRevision((value) => value + 1) }}>Reintentar permisos</button></div>}
      <ColegioTabs value={section} permissions={permissions} disabled={busy} onChange={changeSection} />
      <div id="school-panel-informacion" role="tabpanel" aria-labelledby="school-tab-informacion" hidden={section !== 'informacion'} tabIndex={0}>
      {error && <p className="schools-error" role="alert">{error}</p>}
      {success && <p className="schools-success" role="status">{success}</p>}
      <form onSubmit={(event) => { void save(event) }}>
        <fieldset disabled={busy || !canEdit} className="schools-fieldset">
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
              setComunas([])
              setComunasError(null)
              setLoadingComunas(!!nextRegion)
            }}
          />
          {comunasError && <p className="schools-error" role="alert">{comunasError}</p>}
        </fieldset>
        <div className="schools-editor-actions">
          {canEdit && <button className="schools-primary" type="submit" disabled={busy || loadingComunas || !!comunasError}>{working ? 'Procesando...' : 'Guardar cambios'}</button>}
          <button className="schools-secondary" type="button" onClick={onClose} disabled={busy}>Cancelar</button>
        </div>
      </form>
      <section className="schools-form-section schools-status-section">
        <h3>Estado del colegio</h3>
        <p>Estado actual: <strong>{current.activo ? 'Activo' : 'Inactivo'}</strong></p>
        <p>Desactivar es reversible y conserva la información del establecimiento y su historial.</p>
        {canToggle && <button className={current.activo ? 'schools-danger' : 'schools-secondary'} type="button" disabled={busy} onClick={() => { void toggle() }}>
          {current.activo ? 'Desactivar colegio' : 'Reactivar colegio'}
        </button>}
      </section>
      {onRequestDelete && permissions.includes('DELETE_SCHOOL') && (
        <section className="schools-form-section schools-delete-section">
          <h3>Eliminar colegio</h3>
          <p>Se eliminarán lógicamente el colegio y sus cursos, salas y contactos. Se conservarán las asignaciones históricas y la auditoría. Primero debes cancelar o reasignar las asignaciones futuras vigentes.</p>
          <button type="button" className="schools-danger" disabled={busy} onClick={() => onRequestDelete(current)}>
            Eliminar colegio
          </button>
        </section>
      )}
      </div>
      <div id="school-panel-contactos" role="tabpanel" aria-labelledby="school-tab-contactos" hidden={section !== 'contactos'} tabIndex={0}>
      {visited.includes('contactos') && <>
        {Boolean(current.nombre_contacto || current.telefono_contacto || current.email_contacto) && <section className="schools-form-section schools-legacy-contact">
          <h3>Contacto anterior (solo consulta)</h3>
          <p>Estos datos históricos no están vinculados con Asignaciones. Registra a la persona como contacto para usarla en nuevas actividades.</p>
          <p><strong>Nombre:</strong> {current.nombre_contacto || '—'}</p>
          <p><strong>Teléfono:</strong> {current.telefono_contacto || '—'}</p>
          <p><strong>Correo:</strong> {current.email_contacto || '—'}</p>
        </section>}
        <ColegioContactos colegioId={current.id} colegioActivo={current.activo} permissions={permissions} onWorkingChange={setChildWorking} />
      </>}
      </div>
      <div id="school-panel-cursos" role="tabpanel" aria-labelledby="school-tab-cursos" hidden={section !== 'cursos'} tabIndex={0}>
        {visited.includes('cursos') && <ColegioCursos colegioId={current.id} colegioActivo={current.activo} permissions={permissions} onWorkingChange={setChildWorking} />}
      </div>
      <div id="school-panel-salas" role="tabpanel" aria-labelledby="school-tab-salas" hidden={section !== 'salas'} tabIndex={0}>
        {visited.includes('salas') && <ColegioSalas colegioId={current.id} colegioActivo={current.activo} permissions={permissions} onWorkingChange={setChildWorking} />}
      </div>
    </div>
  )
}

export default ColegioEditForm
