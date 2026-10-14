import LoadingIndicator from '../LoadingIndicator'
import { useEffect, useState, type FormEvent } from 'react'
import { addParticipante, getOpcionesParticipantes } from '../../services/asignacionesService'
import { useConfirmation } from '../../hooks/useConfirmation'

interface Props {
  assignment: string
  existing: string[]
  onAdded: () => Promise<void>
  onClose: () => void
}

export default function AgregarParticipanteForm({ assignment, existing, onAdded, onClose }: Props) {
  const [options, setOptions] = useState<Awaited<ReturnType<typeof getOpcionesParticipantes>> | null>(null)
  const [usuario, setUsuario] = useState('')
  const [tipo, setTipo] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const { confirm, confirmationDialog } = useConfirmation()
  useEffect(() => {
    let active = true
    void getOpcionesParticipantes().then((data) => { if (active) setOptions(data) })
      .catch((cause: unknown) => { if (active) setError(cause instanceof Error ? cause.message : 'No se pudieron cargar las opciones.') })
    return () => { active = false }
  }, [])
  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!usuario || !tipo || busy) return
    if (!await confirm({ title: 'Agregar participante', confirmLabel: 'Agregar y notificar',
      message: 'El nuevo participante recibirá una invitación para aceptar o rechazar. Se conservarán los participantes y respuestas existentes.' })) return
    setBusy(true); setError('')
    let added = false
    try { await addParticipante(assignment, usuario, tipo); added = true; await onAdded(); onClose() }
    catch (cause) { setError(added ? 'El participante se agregó. Cierra el formulario y actualiza el detalle para verlo.' : cause instanceof Error ? cause.message : 'No fue posible agregar al participante.') }
    finally { setBusy(false); if (added) { setUsuario(''); setTipo('') } }
  }
  const available = options?.participantes.filter((person) => !existing.includes(person.id)) ?? []
  return <form className="assignments-form-section" onSubmit={(event) => void submit(event)}>
    <h3>Agregar participante</h3>
    {error && <p className="assignments-error" role="alert">{error}</p>}
    {!options && !error ? <LoadingIndicator /> : options && <>
      {!available.length && <p>No hay otros participantes activos disponibles.</p>}
      <div className="assignments-form-grid"><label>Participante<select required value={usuario} disabled={busy} onChange={(event) => setUsuario(event.target.value)}><option value="">Selecciona una persona</option>{available.map((person) => <option key={person.id} value={person.id}>{[person.nombres, person.apellido_paterno, person.apellido_materno].filter(Boolean).join(' ')}</option>)}</select></label>
        <label>Tipo de participación<select required value={tipo} disabled={busy} onChange={(event) => setTipo(event.target.value)}><option value="">Selecciona un tipo</option>{options.tipos_participacion.map((entry) => <option key={entry.id} value={entry.id}>{entry.nombre}</option>)}</select></label></div></>}
    <div className="assignments-editor-actions"><button className="assignments-primary" disabled={busy || !usuario || !tipo}>{busy ? 'Agregando…' : 'Agregar participante'}</button><button type="button" className="assignments-secondary" disabled={busy} onClick={onClose}>Cerrar</button></div>
    {confirmationDialog}
  </form>
}
