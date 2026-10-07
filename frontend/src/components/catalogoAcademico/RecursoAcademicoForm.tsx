/** Edición del catálogo: niveles compartidos por asignatura y espacios con padre fijo. */
import { useState, type FormEvent } from 'react'
import type { DatosAcademicos, EntidadAcademica, NivelAcademico, RecursoAcademico } from '../../types/catalogoAcademico'

interface Props {
  entidad: EntidadAcademica
  recurso: RecursoAcademico | null
  asignatura: RecursoAcademico | null
  niveles: NivelAcademico[]
  onSave: (datos: DatosAcademicos) => Promise<void>
  onCancel: () => void
}

export default function RecursoAcademicoForm({ entidad, recurso, asignatura, niveles, onSave, onCancel }: Props) {
  const [nombre, setNombre] = useState(recurso?.nombre ?? '')
  const [descripcion, setDescripcion] = useState(recurso?.descripcion ?? '')
  const [nivelIds, setNivelIds] = useState(recurso?.nivel_ids ?? [])
  const [orden, setOrden] = useState(recurso?.orden?.toString() ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const subject = entidad === 'asignaturas'

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (busy) return
    const levels = nivelIds.filter((id) => niveles.some((nivel) => nivel.id === id && nivel.activo))
    if (subject && !levels.length) { setError('Selecciona al menos un nivel activo.'); return }
    if (!subject && !asignatura?.activo) { setError('Selecciona una asignatura activa.'); return }
    const datos: DatosAcademicos = {
      nombre: nombre.trim(), descripcion: descripcion.trim() || null,
      ...(subject ? { nivel_ids: levels } : { ramo_id: asignatura!.id, orden: orden === '' ? null : Number(orden) }),
    }
    setBusy(true); setError('')
    try { await onSave(datos) }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar el recurso.'); setBusy(false) }
  }

  return <form className="assignments-editor academic-editor" onSubmit={(event) => void submit(event)}>
    <h2>{recurso ? 'Editar' : 'Crear'} {subject ? 'asignatura' : 'espacio'}</h2>
    {!subject && <p>Asignatura: <strong>{asignatura?.nombre}</strong></p>}
    {error && <p className="assignments-error" role="alert">{error}</p>}
    <fieldset disabled={busy} className="assignments-fieldset">
      <div className="assignments-form-grid">
        <label>Nombre<input required maxLength={150} value={nombre} onChange={(event) => setNombre(event.target.value)} /></label>
        {!subject && <label>Orden (opcional)<input type="number" min={0} max={9999} step={1} value={orden} onChange={(event) => setOrden(event.target.value)} /></label>}
      </div>
      <label className="academic-description">Descripción (opcional)<textarea rows={3} maxLength={2000} value={descripcion} onChange={(event) => setDescripcion(event.target.value)} /></label>
      {subject && <section className="assignments-form-section"><h3>Niveles habilitados</h3>
        <p>Esta asignatura estará disponible en todos los colegios para los niveles seleccionados.</p>
        {nivelIds.some((id) => !niveles.some((nivel) => nivel.id === id && nivel.activo)) && <p className="assignments-warning">Hay niveles inactivos asociados. Al guardar se retirarán; la API comprobará las asignaciones vigentes.</p>}
        <div className="academic-levels">{niveles.filter((nivel) => nivel.activo).map((nivel) => <label key={nivel.id}>
          <input type="checkbox" checked={nivelIds.includes(nivel.id)} onChange={(event) => setNivelIds((previous) => event.target.checked ? [...previous, nivel.id] : previous.filter((id) => id !== nivel.id))} />{nivel.nombre}
        </label>)}</div>
      </section>}
      <div className="assignments-editor-actions"><button className="assignments-primary" type="submit">{busy ? 'Guardando…' : recurso ? 'Guardar cambios' : 'Crear recurso'}</button>
        <button className="assignments-secondary" type="button" onClick={onCancel}>Cancelar</button></div>
    </fieldset>
  </form>
}
