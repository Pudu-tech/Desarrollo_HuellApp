/**
 * HuellApp · Formulario de instancias.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Capturar la actividad, recursos, contactos y participantes para crear o editar.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Limpia selecciones dependientes y utiliza catálogos recibidos desde la API.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import LoadingIndicator from '../LoadingIndicator'

import { useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { getOpcionesColegio, getOpcionesEspacios, getColegioEdicion, getEspaciosEdicion } from '../../services/asignacionesService'
import type { AsignacionDetail, AsignacionPayload, OpcionesCreacion } from '../../types/asignaciones'
import { useOpcionesDependientes } from '../../hooks/useOpcionesDependientes'
import { useConfirmation } from '../../hooks/useConfirmation'
import { useAuth } from '../../contexts/AuthContext'
import AsignacionParticipantes, { type ParticipanteFila } from './AsignacionParticipantes'
import { TIPOS_ESCOLARES, validarAsignacion } from './asignacionForm'

interface Props {
  opciones: OpcionesCreacion
  onCreate: (payload: AsignacionPayload) => Promise<AsignacionDetail>
  onClose: () => void
  initial?: AsignacionPayload
  initialDate?: string
}

/** Los valores vacíos son selecciones pendientes; nunca UUID ficticios. */
const emptyPayload = (): AsignacionPayload => ({
  tipo_actividad_id: '', colegio_id: null, coordinador_id: null, curso_colegio_id: null, ramo_id: null,
  espacio_reflexion_id: null, espacio_encuentro_id: null, fecha: '', hora_inicio: '08:00', hora_fin: '08:00',
  lugar: null, observacion: null, participantes: [], contactos: [],
})

export default function AsignacionCreateForm({ opciones, onCreate, onClose, initial, initialDate }: Props) {
  const editing = !!initial
  const { user } = useAuth()
  const [form, setForm] = useState<AsignacionPayload>(() => initial ?? { ...emptyPayload(), fecha: initialDate ?? '' })
  const [participantes, setParticipantes] = useState<ParticipanteFila[]>(() => initial ? initial.participantes.map((item, key) => ({ ...item, key })) : [{ key: 0, usuario_id: '', tipo_participacion_id: '' }])
  const nextRow = useRef(1)
  const submitting = useRef(false)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState('')
  const { confirm, confirmationDialog } = useConfirmation()
  const tipo = opciones.tipos_actividad.find((item) => item.id === form.tipo_actividad_id)
  const escolar = TIPOS_ESCOLARES.has(tipo?.codigo ?? '')
  const academica = tipo?.codigo === 'ESPACIO_REFLEXION' || tipo?.codigo === 'ESPACIO_ENCUENTRO'
  const colegio = useOpcionesDependientes(escolar ? form.colegio_id ?? '' : '', editing ? getColegioEdicion : getOpcionesColegio)
  const espacios = useOpcionesDependientes(academica ? form.ramo_id ?? '' : '', editing ? getEspaciosEdicion : getOpcionesEspacios)
  const curso = colegio.data?.cursos.find((item) => item.id === form.curso_colegio_id)
  const ramos = opciones.ramos.filter((item) => curso && item.nivel_ids.includes(curso.nivel_curso_id))
  const espacioOptions = tipo?.codigo === 'ESPACIO_REFLEXION' ? espacios.data?.reflexion : espacios.data?.encuentro

  const coordinadores = colegio.data?.coordinadores ?? []
  const coordinadorId = colegio.data
    ? user?.role_code === 'COORDINADOR' ? user.id
      : coordinadores.length === 1 ? coordinadores[0].id
        : coordinadores.find((item) => item.id === form.coordinador_id)?.id ?? null
    : form.coordinador_id
  const coordinador = coordinadores.find((item) => item.id === coordinadorId)
  const limitarMonitores = !editing && (
    user?.role_code === 'COORDINADOR'
    || (user?.role_code === 'DIRECTIVA' && escolar && !!form.colegio_id
      && (!colegio.data || coordinadores.length > 0))
  )
  const monitorIds = new Set(coordinador?.monitor_ids)
  const usuarios = limitarMonitores
    ? opciones.participantes.filter((item) => (
      (item.role_code === 'MONITOR' && monitorIds.has(item.id))
      || (user?.role_code === 'COORDINADOR' && item.id === user.id)
    ))
    : opciones.participantes
  const filas = limitarMonitores ? participantes.map((item) => (
    item.usuario_id && !usuarios.some((user) => user.id === item.usuario_id)
      ? { ...item, usuario_id: '' }
      : item
  )) : participantes

  /** Actualiza un campo y limpia el error de validación de la edición anterior. */
  function change<K extends keyof AsignacionPayload>(key: K, value: AsignacionPayload[K]) {
    setForm((previous) => ({ ...previous, [key]: value }))
    setError('')
  }

  /* ============================================================
     VALIDACIÓN Y CREACIÓN ATÓMICA CONFIRMADA
     ============================================================ */
  /** Normaliza y valida el formulario y sus opciones; bloquea envíos simultáneos con una referencia. */
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (submitting.current) return
    const payload: AsignacionPayload = {
      ...form, coordinador_id: coordinadorId, lugar: form.lugar?.trim() || null, observacion: form.observacion?.trim() || null,
      participantes: filas.map(({ usuario_id, tipo_participacion_id }) => ({ usuario_id, tipo_participacion_id })),
    }
    const validation = validarAsignacion(payload, tipo?.codigo ?? '')
    if (validation) { setError(validation); return }
    if (colegio.loading || espacios.loading || colegio.error || espacios.error) { setError('Espera a que se carguen correctamente las opciones dependientes.'); return }
    if (payload.participantes.some((item) => !usuarios.some((user) => user.id === item.usuario_id)
      || !opciones.tipos_participacion.some((role) => role.id === item.tipo_participacion_id))) { setError('Uno de los participantes o tipos no está disponible.'); return }
    if (escolar && (!opciones.colegios.some((item) => item.id === payload.colegio_id)
      || payload.contactos.some((item) => !colegio.data?.contactos.some((contacto) => contacto.id === item.contacto_colegio_id))
      || (payload.curso_colegio_id && !curso))) { setError('Revisa los recursos y contactos del colegio seleccionado.'); return }
    if (academica && (!ramos.some((item) => item.id === payload.ramo_id)
      || !espacioOptions?.some((item) => item.id === (payload.espacio_reflexion_id ?? payload.espacio_encuentro_id)))) { setError('El ramo y el espacio deben corresponder al curso seleccionado.'); return }
    submitting.current = true
    setError('')
    try {
      if (!await confirm({ title: editing ? '¿Guardar cambios?' : '¿Crear instancia?', confirmLabel: editing ? 'Sí, guardar cambios' : 'Sí, crear instancia',
        message: editing ? <>En instancias pendientes o confirmadas, los cambios de fecha, horario, contexto o participantes pueden solicitar una nueva confirmación. Si la instancia está No realizada, se guardará como corrección administrativa sin reabrirla ni reenviar invitaciones.</> : <>Vas a crear <strong>{tipo?.nombre}</strong> para el {payload.fecha.split('-').reverse().join('/')} de {payload.hora_inicio} a {payload.hora_fin}, con {payload.participantes.length} participante(s).</> })) return
      setWorking(true)
      await onCreate(payload)
    } catch (cause) {
      await confirm({
        title: editing ? 'No se pudieron guardar los cambios' : 'No se pudo crear la instancia',
        message: cause instanceof Error ? cause.message : 'Ocurrió un error al procesar la solicitud.',
        confirmLabel: 'Entendido',
        acknowledgeOnly: true,
      })
    } finally { submitting.current = false; setWorking(false) }
  }

  return <div className="assignments-editor">
    {confirmationDialog}
    <div className="assignments-panel-heading"><div><h2>{editing ? 'Editar instancia' : 'Nueva instancia'}</h2><p>{editing ? 'Actualiza los datos y participantes de la instancia. El tipo de actividad se conserva.' : 'Completa los datos de la actividad y las personas que participarán.'}</p></div>
      <button type="button" className="assignments-secondary" disabled={working} onClick={onClose}>Volver al listado</button>
    </div>
    <form onSubmit={(event) => void save(event)}>
      <fieldset className="assignments-fieldset" disabled={working}>
        <section className="assignments-form-section"><h3>Actividad y horario</h3>
          <div className="assignments-form-grid">
            <label>Tipo de actividad<select required disabled={editing} value={form.tipo_actividad_id} onChange={(event) => {
              setForm((previous) => ({ ...previous, tipo_actividad_id: event.target.value, colegio_id: null, coordinador_id: null, curso_colegio_id: null, ramo_id: null, espacio_reflexion_id: null, espacio_encuentro_id: null, contactos: [], lugar: null }))
              setError('')
            }}><option value="">Seleccionar actividad</option>{opciones.tipos_actividad.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
            <label>Fecha<input type="date" required value={form.fecha} onChange={(event) => change('fecha', event.target.value)} /></label>
            <label>Hora de inicio<input type="time" required value={form.hora_inicio} onChange={(event) => change('hora_inicio', event.target.value)} /></label>
            <label>Hora de término<input type="time" required value={form.hora_fin} onChange={(event) => change('hora_fin', event.target.value)} /></label>
          </div>
        </section>
        {escolar && <section className="assignments-form-section"><h3>Establecimiento y contactos</h3>
          {!opciones.colegios.length && <p className="assignments-warning">No hay colegios activos disponibles. Registra o reactiva un colegio antes de crear esta actividad.</p>}
          <div className="assignments-form-grid">
            <label>Colegio<select required value={form.colegio_id ?? ''} onChange={(event) => {
              setForm((previous) => ({ ...previous, colegio_id: event.target.value || null, coordinador_id: null, curso_colegio_id: null, ramo_id: null, espacio_reflexion_id: null, espacio_encuentro_id: null, contactos: [] }))
              setError('')
            }}><option value="">Seleccionar colegio</option>{opciones.colegios.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
            {user?.role_code !== 'COORDINADOR' && coordinadores.length > 0 && <label>Coordinador responsable<select required value={coordinadorId ?? ''} disabled={coordinadores.length === 1} onChange={(event) => change('coordinador_id', event.target.value || null)}><option value="">Seleccionar coordinador</option>{coordinadores.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>}
            <label>Curso{!academica && ' (opcional)'}<select required={academica} disabled={!form.colegio_id || colegio.loading || !!colegio.error} value={form.curso_colegio_id ?? ''} onChange={(event) => {
              setForm((previous) => ({ ...previous, curso_colegio_id: event.target.value || null, ramo_id: null, espacio_reflexion_id: null, espacio_encuentro_id: null }))
              setError('')
            }}><option value="">Seleccionar curso</option>{colegio.data?.cursos.map((item) => <option key={item.id} value={item.id}>{item.nombre_mostrado} · {item.anio}</option>)}</select></label>
          </div>
          {colegio.loading && <LoadingIndicator />}
          {colegio.data && !colegio.data.coordinadores.length && user?.role_code !== 'COORDINADOR' && <p className="assignments-warning">Este colegio no tiene un coordinador activo asignado. La instancia se guardará sin coordinador responsable.</p>}
          {academica && colegio.data && !colegio.data.cursos.length && <p className="assignments-warning">Esta actividad requiere cursos activos. Completa los cursos que faltan desde la ficha del colegio.</p>}
          {colegio.error && <div role="alert"><p className="assignments-error">{colegio.error}</p><button className="assignments-secondary" type="button" onClick={colegio.retry}>Reintentar recursos</button></div>}
          {colegio.data && <><p>Selecciona las personas de contacto que correspondan.</p><div className="assignments-contacts">
            {colegio.data.contactos.map((item) => {
              const checked = form.contactos.some((contacto) => contacto.contacto_colegio_id === item.id)
              return <label key={item.id}><input type="checkbox" checked={checked} onChange={(event) => change('contactos', event.target.checked ? [...form.contactos, { contacto_colegio_id: item.id }] : form.contactos.filter((contacto) => contacto.contacto_colegio_id !== item.id))} />
                {[item.nombre, item.apellido_paterno, item.apellido_materno].filter(Boolean).join(' ')}{item.cargo ? ` · ${item.cargo}` : ''}
              </label>
            })}
            {!colegio.data.contactos.length && <p className="assignments-warning">Este colegio no tiene contactos activos. Agrégalos desde la ficha del colegio antes de crear la instancia.</p>}
          </div></>}
        </section>}
        {academica && <section className="assignments-form-section"><h3>Contexto académico</h3><div className="assignments-form-grid">
          <label>Asignatura<select required disabled={!curso} value={form.ramo_id ?? ''} onChange={(event) => {
            setForm((previous) => ({ ...previous, ramo_id: event.target.value || null, espacio_reflexion_id: null, espacio_encuentro_id: null }))
            setError('')
          }}><option value="">Seleccionar asignatura</option>{ramos.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
          <label>Espacio de {tipo?.codigo === 'ESPACIO_REFLEXION' ? 'reflexión' : 'encuentro'}<select required disabled={!form.ramo_id || espacios.loading || !!espacios.error} value={form.espacio_reflexion_id ?? form.espacio_encuentro_id ?? ''}
            onChange={(event) => change(tipo?.codigo === 'ESPACIO_REFLEXION' ? 'espacio_reflexion_id' : 'espacio_encuentro_id', event.target.value || null)}>
            <option value="">Seleccionar espacio</option>{espacioOptions?.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}
          </select></label>
        </div>
          {curso && !ramos.length && <p className="assignments-warning">No hay asignaturas activas habilitadas para este nivel. Adminístralas en el <Link to="/app/catalogo-academico">Catálogo académico</Link> y vuelve a abrir el formulario.</p>}
          {espacios.loading && <LoadingIndicator />}
          {espacios.error && <div role="alert"><p className="assignments-error">{espacios.error}</p><button type="button" className="assignments-secondary" onClick={espacios.retry}>Reintentar espacios</button></div>}
          {espacios.data && !espacioOptions?.length && <p className="assignments-warning">No hay espacios activos disponibles para este ramo y actividad.</p>}
        </section>}
        {tipo && !escolar && <section className="assignments-form-section"><h3>Lugar</h3><label>Lugar de la actividad<input required maxLength={250} value={form.lugar ?? ''} onChange={(event) => change('lugar', event.target.value)} /></label></section>}
        {limitarMonitores && user?.role_code === 'COORDINADOR' && !form.colegio_id && <p>Selecciona un colegio para ver tus monitores asignados.</p>}
        {limitarMonitores && user?.role_code === 'DIRECTIVA' && coordinadores.length > 1 && !coordinador && <p>Selecciona un coordinador para ver sus monitores.</p>}
        {limitarMonitores && coordinador && !usuarios.some((item) => item.role_code === 'MONITOR') && <p className="assignments-warning">Este coordinador no tiene monitores activos asignados en el colegio.</p>}
        <AsignacionParticipantes rows={filas} usuarios={usuarios} tipos={opciones.tipos_participacion} onChange={setParticipantes}
          soloMonitores={limitarMonitores && user?.role_code === 'DIRECTIVA'}
          onAdd={() => setParticipantes((previous) => [...previous, { key: nextRow.current++, usuario_id: '', tipo_participacion_id: '' }])} />
        {editing && <p className="assignments-warning">Los cambios de participantes conservan el historial anterior. En instancias pendientes o confirmadas puede solicitarse una nueva respuesta; en una instancia No realizada la edición es administrativa y no envía nuevas invitaciones.</p>}
        <section className="assignments-form-section"><h3>Observaciones</h3><label>Observación (opcional)<textarea maxLength={2000} rows={3} value={form.observacion ?? ''} onChange={(event) => change('observacion', event.target.value)} /></label></section>
      </fieldset>
      {error && <p className="assignments-error" role="alert">{error}</p>}
      <div className="assignments-editor-actions">
        <button className="assignments-primary" type="submit" disabled={working || colegio.loading || espacios.loading || !!colegio.error || !!espacios.error}>{working ? 'Guardando…' : editing ? 'Guardar cambios' : 'Crear instancia'}</button>
        <button className="assignments-secondary" type="button" disabled={working} onClick={onClose}>Cancelar</button>
      </div>
    </form>
  </div>
}
