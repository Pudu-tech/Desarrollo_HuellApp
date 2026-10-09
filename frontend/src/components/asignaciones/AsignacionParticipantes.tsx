/**
 * HuellApp · Selección de participantes para una nueva asignación.
 * Los usuarios elegibles y tipos se consultan en backend; no se admite duplicación.
 */
import type { OpcionCodigo, ParticipanteOpcion, ParticipantePayload } from '../../types/asignaciones'

export interface ParticipanteFila extends ParticipantePayload { key: number }
interface Props {
  rows: ParticipanteFila[]
  usuarios: ParticipanteOpcion[]
  tipos: OpcionCodigo[]
  onChange: (rows: ParticipanteFila[]) => void
  onAdd: () => void
}

export default function AsignacionParticipantes({ rows, usuarios, tipos, onChange, onAdd }: Props) {
  return <section className="assignments-form-section">
    <h3>Participantes</h3>
    <p>Agrega al menos una persona e indica su participación en la actividad.</p>
    {!usuarios.length && <p className="assignments-warning">No hay participantes activos disponibles. Deben existir usuarios DIRECTIVA, COORDINADOR o MONITOR.</p>}
    {rows.map((row, index) => <div className="assignments-participant-row" key={row.key}>
      <label>Participante {index + 1}<select required value={row.usuario_id} onChange={(event) => onChange(rows.map((item) => item.key === row.key ? { ...item, usuario_id: event.target.value } : item))}>
        <option value="">Seleccionar persona</option>
        {usuarios.map((user) => <option key={user.id} value={user.id} disabled={rows.some((item) => item.key !== row.key && item.usuario_id === user.id)}>
          {[user.nombres, user.apellido_paterno, user.apellido_materno].filter(Boolean).join(' ')} · {user.role_code}
        </option>)}
      </select></label>
      <label>Tipo de participación<select required value={row.tipo_participacion_id} onChange={(event) => onChange(rows.map((item) => item.key === row.key ? { ...item, tipo_participacion_id: event.target.value } : item))}>
        <option value="">Seleccionar participación</option>
        {tipos.map((tipo) => <option key={tipo.id} value={tipo.id}>{tipo.nombre}</option>)}
      </select></label>
      <button type="button" className="assignments-secondary" disabled={rows.length === 1} onClick={() => onChange(rows.filter((item) => item.key !== row.key))} aria-label={`Quitar participante ${index + 1}`}>Quitar</button>
    </div>)}
    <button type="button" className="assignments-secondary" disabled={rows.length >= usuarios.length} onClick={onAdd}>+ Agregar participante</button>
  </section>
}
