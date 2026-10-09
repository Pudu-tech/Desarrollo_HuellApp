/** Datos legibles de una asignación personal, sin datos de otros participantes. */
import type { ParticipacionPropia } from '../../services/participacionesService'

export default function PersonalAssignmentInfo({ info }: { info: ParticipacionPropia }) {
  const timestamp = (value: string) => new Date(value).toLocaleString('es-CL', { timeZone: 'America/Santiago', dateStyle: 'short', timeStyle: 'short' })
  return <><h2>{info.actividad}</h2><dl className="assignments-detail-grid">
    {info.recibida_at && <div><dt>Recibida el</dt><dd>{timestamp(info.recibida_at)}</dd></div>}
    {info.actualizada_at && <div><dt>Actualizada el</dt><dd>{timestamp(info.actualizada_at)}</dd></div>}
    <div><dt>Colegio / lugar</dt><dd>{info.colegio ?? info.lugar ?? '—'}</dd></div>
    <div><dt>Fecha y horario</dt><dd>{info.fecha.split('-').reverse().join('/')} · {info.hora_inicio.slice(0, 5)} – {info.hora_fin.slice(0, 5)}</dd></div>
    {info.curso && <div><dt>Curso</dt><dd>{info.curso}</dd></div>}
    {info.sala && <div><dt>Sala</dt><dd>{info.sala}</dd></div>}
    {info.asignatura && <div><dt>Asignatura</dt><dd>{info.asignatura}</dd></div>}
    {info.espacio && <div><dt>Espacio</dt><dd>{info.espacio}</dd></div>}
    {info.tipo_participacion && <div><dt>Mi participación</dt><dd>{info.tipo_participacion}</dd></div>}
    {info.observacion && <div><dt>Observación</dt><dd>{info.observacion}</dd></div>}
  </dl></>
}
