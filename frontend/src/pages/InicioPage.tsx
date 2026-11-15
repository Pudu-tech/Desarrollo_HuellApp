/**
 * HuellApp · Resumen de inicio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Presentar métricas de las instancias visibles a Directiva y Coordinador.
 * - Mantener las métricas personales de los demás roles.
 * - Mostrar agenda de instancias visibles a Directiva y Coordinador, y personal a Monitor.
 * - Mantener el resumen administrativo de Superadmin.
 *
 * SECURITY
 * ------------------------------------------------------------
 * El calendario solo ofrece accesos permitidos por rol. FastAPI y PostgreSQL
 * siguen siendo la fuente real de autorización y reglas de negocio.
 */
import SortButton from '../components/common/SortButton'
import { useListSort } from '../hooks/useListSort'
import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { getAsignacionesResumen } from '../services/asignacionesService'
import { recursoRequest } from '../services/recursosService'
import type { ParticipacionPropia } from '../services/participacionesService'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import LoadingIndicator from '../components/LoadingIndicator'
import '../styles/inicio.css'
import { useProfilePhoto, updateProfilePhoto } from '../hooks/useProfilePhoto'

type Activity = {
  id: string
  fecha: string
  hora: string
  nombre: string
  lugar: string
  estado: string
  admiteRespuesta?: boolean
  asistencia: Record<string, number>
  asignadosA?: string[]
}

const today = () => new Intl.DateTimeFormat('sv-SE', { timeZone: 'America/Santiago' }).format(new Date())
const key = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const labels: Record<string, string> = {
  PENDIENTE: 'Pendiente', CONFIRMADA: 'Confirmada', REALIZADA: 'Realizada', CANCELADA: 'Cancelada',
  NO_REALIZADA: 'No realizada', ACEPTADA: 'Aceptada', RECHAZADA: 'Rechazada', PRESENTE: 'Presente',
  AUSENTE: 'Ausente', JUSTIFICADA: 'Justificada', NO_REQUERIDA: 'No requerida',
}

/** Formatea una fecha del calendario incluyendo el nombre del día. */
function formatCalendarDate(date: string) {
  const value = new Intl.DateTimeFormat('es-CL', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Santiago',
  }).format(new Date(`${date}T12:00:00-03:00`))
  return value.charAt(0).toLocaleUpperCase('es-CL') + value.slice(1)
}

export default function InicioPage() {
  const { user } = useAuth()
  const navigate = useNavigate()
  const photoUrl = useProfilePhoto(user?.id, '/mi-perfil')
  const isMonitor = user?.role_code === 'MONITOR'
  const isDirectiva = user?.role_code === 'DIRECTIVA'
  const isCoordinador = user?.role_code === 'COORDINADOR'
  const hasManagementStats = isDirectiva || isCoordinador
  const isSuperadmin = user?.role_code === 'SUPERADMIN'
  const hasPersonalCalendar = !isSuperadmin
  const canCreateFromCalendar = user?.role_code === 'DIRECTIVA' || user?.role_code === 'COORDINADOR'
  const sorting = useListSort<string>('fecha')
  const [items, setItems] = useState<Activity[] | null>(null)
  const [personalItems, setPersonalItems] = useState<ParticipacionPropia[] | null>(null)
  const [error, setError] = useState('')
  const [selected, setSelected] = useState(today)
  const [createDate, setCreateDate] = useState<string | null>(null)
  const [detailEvent, setDetailEvent] = useState<Activity | null>(null)
  const [month, setMonth] = useState(() => new Date(`${today().slice(0, 7)}-01T12:00:00`))

  async function readPersonal(fresh = false): Promise<ParticipacionPropia[]> {
    return recursoRequest<ParticipacionPropia[]>('/mi-participacion', 'GET', undefined, fresh)
  }

  /** Obtiene el resumen global solo cuando el rol necesita información de equipo. */
  async function read(fresh = false): Promise<Activity[]> {
    if (isMonitor) {
      const rows = await readPersonal(fresh)
      return rows.map((r) => ({
        id: r.asignacion_id, fecha: r.fecha, hora: r.hora_inicio.slice(0, 5), nombre: r.actividad,
        lugar: r.colegio || r.lugar || 'Por definir', estado: r.asignacion_estado,
        admiteRespuesta: r.admite_respuesta, asistencia: {},
      }))
    }
    const data = await getAsignacionesResumen(fresh)
    return data.items.map((r) => ({
      id: r.id, fecha: r.fecha, hora: r.hora_inicio.slice(0, 5),
      nombre: data.catalogos.tipos_actividad.find((t) => t.id === r.tipo_actividad_id)?.nombre || 'Actividad',
      lugar: data.catalogos.colegios.find((c) => c.id === r.colegio_id)?.nombre || r.lugar || 'Por definir',
      estado: data.catalogos.estados.find((e) => e.id === r.estado_id)?.codigo || 'PENDIENTE',
      asistencia: r.asistencia_resumen || {},
      asignadosA: r.asignados_a || [],
    }))
  }

  useEffect(() => {
    let active = true
    Promise.all([read(), readPersonal()]).then(([rows, ownRows]) => {
      if (active) { setItems(rows); setPersonalItems(ownRows); setError('') }
    }).catch((cause: unknown) => { if (active) setError(cause instanceof Error ? cause.message : 'No fue posible cargar el inicio.') })
    return () => { active = false }
    // La sección se vuelve a montar al cambiar de usuario.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, isMonitor])

  useVisibleRefresh(async (active) => {
    try {
      const [rows, ownRows] = await Promise.all([read(true), readPersonal(true)])
      if (active()) { setItems(rows); setPersonalItems(ownRows); setError('') }
    } catch { /* Conserva los datos durante fallos transitorios. */ }
  }, items !== null && personalItems !== null, 30000)

  const sortActivities = (rows: Activity[]) => sorting.order(rows, {
    fecha: (r) => `${r.fecha} ${r.hora}`, nombre: (r) => r.nombre, lugar: (r) => r.lugar,
  })
  const globalUpcoming = sortActivities((items || []).filter((r) => r.fecha >= today() && !['RECHAZADA', 'CANCELADA', 'NO_REALIZADA', 'REALIZADA'].includes(r.estado)))
  const ownItems = personalItems || []
  const ownActivities: Activity[] = ownItems.map((r) => ({
    id: r.asignacion_id, fecha: r.fecha, hora: r.hora_inicio.slice(0, 5), nombre: r.actividad,
    lugar: r.colegio || r.lugar || 'Por definir', estado: r.asignacion_estado,
    admiteRespuesta: r.admite_respuesta, asistencia: {},
  }))
  const ownUpcoming = sortActivities(ownActivities.filter((r) => r.fecha >= today() && ['PENDIENTE', 'CONFIRMADA'].includes(r.estado)))
  const ownPending = ownItems.filter((r) => r.estado === 'PENDIENTE' && r.admite_respuesta)
  const ownCompleted = ownItems.filter((r) => r.asignacion_estado === 'REALIZADA')
  const monthKey = key(month).slice(0, 7)
  const visiblePersonal = ownActivities.filter((r) => r.fecha.startsWith(monthKey))
  const visibleTeam = (items || []).filter((r) => r.fecha.startsWith(monthKey))
  const calendarItems = hasManagementStats ? visibleTeam : visiblePersonal
  const dayItems = sortActivities(calendarItems.filter((r) => r.fecha === selected))

  /** Agrupa la carga mensual en bloques de siete días para una lectura rápida. */
  const weeklyActivitySource = calendarItems
    .filter((r) => r.estado !== 'CANCELADA')
  const weeklyActivity = Array.from({ length: 5 }, (_, index) => ({
    label: `Sem ${index + 1}`,
    count: weeklyActivitySource.filter((r) => Math.floor((Number(r.fecha.slice(8, 10)) - 1) / 7) === index).length,
  }))
  const maxWeeklyActivity = Math.max(...weeklyActivity.map((item) => item.count), 1)
  const monthLabel = new Intl.DateTimeFormat('es-CL', { month: 'long', year: 'numeric' }).format(month)

  /** Cuenta cuántas instancias del mes tiene cada integrante visible para Directiva. */
  const teamLoad = isDirectiva
    ? Array.from(visibleTeam.filter((r) => r.estado !== 'CANCELADA').reduce((acc, item) => {
        for (const name of item.asignadosA || []) acc.set(name, (acc.get(name) || 0) + 1)
        return acc
      }, new Map<string, number>()).entries())
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, 'es-CL'))
    : []
  const maxTeamLoad = Math.max(...teamLoad.map((item) => item.count), 1)

  const move = (amount: number) => {
    const next = new Date(month.getFullYear(), month.getMonth() + amount, 1, 12)
    setMonth(next)
    setSelected(key(next))
  }

  const detailPath = (id: string) => isMonitor ? `/app/monitor/asignaciones/${id}` : `/app/asignaciones/${id}`
  const activity = (r: Activity) => <Link className="home-activity" key={r.id} to={detailPath(r.id)}>
    <span className="home-date">{r.fecha.slice(8)} / {r.fecha.slice(5, 7)}<small>{r.hora}</small></span>
    <span><strong>{r.nombre}</strong><small>{r.lugar}</small></span>
    <span className="home-tag">{labels[r.estado] || r.estado}</span>
  </Link>

  const orderControls = <div className="home-list-order" role="group" aria-label="Orden de actividades">
    <SortButton label="Fecha" column="fecha" sort={sorting.sort} onSort={sorting.toggle} />
    <SortButton label="Actividad" column="nombre" sort={sorting.sort} onSort={sorting.toggle} />
    <SortButton label="Colegio / lugar" column="lugar" sort={sorting.sort} onSort={sorting.toggle} />
  </div>

  // La API ya limita las instancias al ámbito autorizado del coordinador.
  const statsItems = items || []
  const statsUpcoming = statsItems.filter((r) => r.fecha >= today() && ['PENDIENTE', 'CONFIRMADA'].includes(r.estado))
  const managementLinks = ['/app/asignaciones', '/app/asignaciones?proximas=1', '/app/asignaciones?estado=REALIZADA', '/app/asignaciones?estado=PENDIENTE']
  const statsLinks = isMonitor
    ? ['/app/monitor/asignaciones', '/app/monitor/asignaciones?orden=proximas', '/app/monitor/asignaciones', '/app/monitor/asignaciones?pendientes=1']
    : hasManagementStats
      ? managementLinks
      : ['/app/mis-asignaciones', '/app/mis-asignaciones', '/app/mis-asignaciones', '/app/mis-asignaciones']
  const stats: Array<[string, number]> = [
    ['Mis instancias Huella', hasManagementStats ? statsItems.length : ownItems.length],
    ['Próximas actividades', hasManagementStats ? statsUpcoming.length : ownUpcoming.length],
    ['Actividades Realizadas', hasManagementStats ? statsItems.filter((r) => r.estado === 'REALIZADA').length : ownCompleted.length],
    ['Actividades por confirmar', hasManagementStats ? statsItems.filter((r) => r.estado === 'PENDIENTE').length : ownPending.length],
  ]

  /**
   * Selecciona una fecha del calendario.
   * Directiva y Coordinador reciben primero una confirmación contextual; Monitor
   * no ejecuta acciones sobre días vacíos y solo navega desde instancias existentes.
   */
  function handleDay(date: string) {
    if (!canCreateFromCalendar) return
    setSelected(date)
    setDetailEvent(null)
    setCreateDate(date)
  }

  /** Abre el formulario existente de creación con la fecha elegida precargada. */
  function createInstanceForSelectedDate() {
    if (!createDate) return
    navigate(`/app/asignaciones?crear=1&fecha=${encodeURIComponent(createDate)}`)
  }

  return <section className="home-dashboard">
    <header className="home-heading"><div className="home-welcome">
      <Link className="home-avatar" to={isMonitor ? '/app/monitor/perfil' : '/app/perfil'} aria-label="Abrir mi perfil">
        {photoUrl ? <img src={photoUrl} alt="" onError={() => { if (user) updateProfilePhoto(user.id, null) }} /> : <span aria-hidden="true">{`${user?.nombres?.charAt(0) || ''}${user?.apellido_paterno?.charAt(0) || ''}`.toLocaleUpperCase('es-CL') || 'H'}</span>}
      </Link>
      <div><span className="home-eyebrow">Tu espacio en HuellApp</span><h2>Hola, {user?.nombres || 'bienvenido'}</h2>
        <p>{hasPersonalCalendar ? 'Tu agenda y tus próximas actividades, en un solo lugar.' : 'Una mirada a las actividades y la asistencia del equipo.'}</p>
      </div></div>
      <span className="home-today">{new Intl.DateTimeFormat('es-CL', { dateStyle: 'long', timeZone: 'America/Santiago' }).format(new Date())}</span>
    </header>

    {error && <div role="alert" className="home-error">{error} <button onClick={() => void Promise.all([read(true), readPersonal(true)]).then(([rows, ownRows]) => { setItems(rows); setPersonalItems(ownRows); setError('') }).catch((cause: unknown) => setError(cause instanceof Error ? cause.message : 'No fue posible cargar el inicio.'))}>Reintentar</button></div>}

    {!items || !personalItems ? !error && <LoadingIndicator /> : <>
      <div className="home-stats">{stats.map(([label, value], index) => <Link to={statsLinks[index]} key={label}><span>{label}</span><strong>{value}</strong></Link>)}</div>

      {hasPersonalCalendar ? <div className="home-columns">
        <article className="home-card">
          <div className="home-calendar-header"><h3>{new Intl.DateTimeFormat('es-CL', { month: 'long', year: 'numeric' }).format(month)}</h3><div>
            <button aria-label="Mes anterior" onClick={() => move(-1)}>‹</button>
            <button onClick={() => { const now = today(); setMonth(new Date(`${now.slice(0, 7)}-01T12:00:00`)); setSelected(now) }}>Hoy</button>
            <button aria-label="Mes siguiente" onClick={() => move(1)}>›</button>
          </div></div>
          <div className="home-calendar">
            {['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'].map((d) => <span className="home-weekday" key={d}>{d}</span>)}
            {Array.from({ length: (month.getDay() + 6) % 7 }, (_, i) => <span key={`empty${i}`} />)}
            {Array.from({ length: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate() }, (_, i) => {
              const date = key(new Date(month.getFullYear(), month.getMonth(), i + 1, 12))
              const events = calendarItems.filter((r) => r.fecha === date)
              return <div key={date} className={`home-day ${date === today() ? 'is-today' : ''} ${date === selected ? 'is-selected' : ''} ${(createDate === date || detailEvent?.fecha === date) ? 'has-popover' : ''}`}>
                <button
                  type="button"
                  className="home-day-action"
                  aria-label={canCreateFromCalendar ? `Opciones para ${date}` : `Día ${date}`}
                  onClick={() => handleDay(date)}
                  disabled={!canCreateFromCalendar}
                ><strong>{i + 1}</strong></button>
                <div className="home-day-events">
                  {events.slice(0, 2).map((event) => <button
                    key={event.id}
                    type="button"
                    className="home-calendar-event"
                    title={`${event.hora} · ${event.nombre}`}
                    onClick={(e) => {
                      e.stopPropagation()
                      setSelected(date)
                      setCreateDate(null)
                      setDetailEvent(event)
                    }}
                  >{event.hora} · {event.nombre}</button>)}
                  {events.length > 2 && <button type="button" className="home-more-events" onClick={() => { setSelected(date); setCreateDate(null); setDetailEvent(null) }}>+{events.length - 2} más</button>}
                </div>

                {createDate === date && canCreateFromCalendar && <div className={`home-calendar-popover ${new Date(`${date}T12:00:00`).getDay() === 0 || new Date(`${date}T12:00:00`).getDay() === 6 ? 'is-left' : ''}`} role="dialog" aria-label={`Crear instancia para ${formatCalendarDate(date)}`}>
                  <button type="button" className="home-calendar-popover-close" aria-label="Cerrar" onClick={(event) => { event.stopPropagation(); setCreateDate(null) }}>×</button>
                  <span className="home-calendar-popover-eyebrow">Nueva instancia</span>
                  <strong className="home-calendar-popover-title">{formatCalendarDate(date)}</strong>
                  <p>¿Qué deseas hacer este día?</p>
                  <div className="home-calendar-popover-actions">
                    <button type="button" className="home-calendar-popover-primary" onClick={(event) => { event.stopPropagation(); createInstanceForSelectedDate() }}>+ Crear instancia</button>
                    <button type="button" className="home-calendar-popover-secondary" onClick={(event) => { event.stopPropagation(); setCreateDate(null) }}>Cancelar</button>
                  </div>
                </div>}

                {detailEvent?.fecha === date && events.some((event) => event.id === detailEvent.id) && <div className={`home-calendar-popover home-calendar-detail-popover ${new Date(`${date}T12:00:00`).getDay() === 0 || new Date(`${date}T12:00:00`).getDay() === 6 ? 'is-left' : ''}`} role="dialog" aria-label={`Consultar ${detailEvent.nombre}`}>
                  <button type="button" className="home-calendar-popover-close" aria-label="Cerrar" onClick={(event) => { event.stopPropagation(); setDetailEvent(null) }}>×</button>
                  <span className="home-calendar-popover-eyebrow">Instancia Huella</span>
                  <strong className="home-calendar-popover-title">{detailEvent.nombre}</strong>
                  <dl className="home-calendar-popover-detail">
                    <div><dt>Fecha</dt><dd>{formatCalendarDate(detailEvent.fecha)}</dd></div>
                    <div><dt>Hora</dt><dd>{detailEvent.hora}</dd></div>
                    <div><dt>Lugar</dt><dd>{detailEvent.lugar}</dd></div>
                    <div><dt>Estado</dt><dd>{labels[detailEvent.estado] || detailEvent.estado}</dd></div>
                  </dl>
                  <button type="button" className="home-calendar-popover-primary" onClick={(event) => { event.stopPropagation(); navigate(detailPath(detailEvent.id)) }}>Consultar instancia</button>
                </div>}
              </div>
            })}
          </div>
          <p className="home-muted">{isDirectiva ? 'El calendario muestra todas las instancias del equipo. Selecciona una fecha para crear una instancia o una actividad existente para consultar su detalle.' : canCreateFromCalendar ? 'Selecciona una fecha y confirma si deseas crear una instancia. Si ya existe una actividad, selecciónala para ver su detalle.' : 'Selecciona una instancia del calendario para consultar su detalle.'}</p>

          <h3>{new Intl.DateTimeFormat('es-CL', { day: 'numeric', month: 'long' }).format(new Date(`${selected}T12:00:00`))}</h3>
          {orderControls}
          {dayItems.length ? dayItems.map(activity) : <p className="home-muted">{isDirectiva ? 'No hay actividades del equipo para este día.' : 'No tienes actividades para este día.'}</p>}
        </article>

        <article className="home-card home-agenda-card"><h3>Lo que viene</h3><p className="home-muted">{isDirectiva ? 'Próximas actividades visibles del equipo.' : 'Tus próximas actividades. Usa las flechas para cambiar el orden.'}</p>
          {orderControls}
          {(hasManagementStats ? globalUpcoming : ownUpcoming).length
            ? (hasManagementStats ? globalUpcoming : ownUpcoming).slice(0, 5).map(activity)
            : <p className="home-muted">{isDirectiva ? 'No hay próximas actividades programadas para el equipo.' : 'Tu agenda está despejada. Aquí aparecerán tus próximas instancias.'}</p>}
          <Link className="home-more" to={hasManagementStats ? '/app/asignaciones' : isMonitor ? '/app/monitor/asignaciones' : '/app/mis-asignaciones'}>{isDirectiva ? 'Ver instancias del equipo' : 'Ver mis instancias'} →</Link>

          <section className="home-monthly-summary" aria-labelledby="home-monthly-title">
            <div className="home-monthly-heading">
              <div>
                <span className="home-monthly-eyebrow">{isDirectiva ? 'Vista de equipo' : 'Mi actividad'}</span>
                <h4 id="home-monthly-title">{isDirectiva ? 'Actividad del equipo' : 'Actividad del mes'}</h4>
              </div>
              <span className="home-monthly-period">{monthLabel}</span>
            </div>

            <div className="home-weekly-bars" aria-label={`Actividad semanal de ${monthLabel}`}>
              {weeklyActivity.map((item) => <div className="home-weekly-row" key={item.label}>
                <span>{item.label}</span>
                <div className="home-weekly-track" aria-hidden="true"><span style={{ width: `${item.count / maxWeeklyActivity * 100}%` }} /></div>
                <strong>{item.count}</strong>
              </div>)}
            </div>

            {isDirectiva && <div className="home-team-load">
              <div className="home-team-load-heading"><h4>Carga por integrante</h4><span>{teamLoad.length} integrantes</span></div>
              {teamLoad.length ? teamLoad.slice(0, 6).map((member) => <div className="home-team-load-row" key={member.name}>
                <span title={member.name}>{member.name}</span>
                <div className="home-team-load-track" aria-hidden="true"><span style={{ width: `${member.count / maxTeamLoad * 100}%` }} /></div>
                <strong>{member.count}</strong>
              </div>) : <p className="home-muted">No hay participantes asignados en este mes.</p>}
              {teamLoad.length > 6 && <p className="home-team-load-more">+{teamLoad.length - 6} integrantes adicionales</p>}
            </div>}
          </section>
        </article>
      </div> : <>
        <div className="home-columns">
          <article className="home-card"><h3>Estado de las instancias</h3><p className="home-muted">Todas las instancias visibles del equipo.</p>
            {['PENDIENTE', 'CONFIRMADA', 'REALIZADA', 'CANCELADA', 'NO_REALIZADA'].map((state, i) => {
              const count = items.filter((r) => r.estado === state).length
              return <Link to={`/app/asignaciones?estado=${state}`} className="home-chart" key={state}><div><span>{labels[state]}</span><strong>{count}</strong></div><div className="home-track"><span style={{ width: `${items.length ? count / items.length * 100 : 0}%`, background: ['#e5b765', '#76a997', '#28616a', '#d07b66', '#97a0ae'][i] }} /></div></Link>
            })}
          </article>
          <article className="home-card"><h3>Asistencia del equipo</h3>
            {['PRESENTE', 'PENDIENTE', 'AUSENTE', 'JUSTIFICADA', 'NO_REQUERIDA'].map((state) => <Link to={`/app/asistencia?estado=${state}`} className="home-attendance" key={state}><span>{labels[state]}</span><strong>{items.reduce((sum, r) => sum + (r.asistencia[state] || 0), 0)}</strong></Link>)}
            <Link className="home-more" to="/app/asistencia">Consultar asistencia →</Link>
          </article>
        </div>
        <article className="home-card"><h3>Próximas actividades del equipo</h3>{orderControls}{globalUpcoming.length ? globalUpcoming.slice(0, 5).map(activity) : <p className="home-muted">No hay próximas actividades programadas.</p>}<Link className="home-more" to="/app/asignaciones">Ver todas las instancias →</Link></article>
      </>}
    </>}
  </section>
}
