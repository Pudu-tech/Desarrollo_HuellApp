/**
 * HuellApp · Listado y creación de instancias.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Consultar, filtrar y ordenar actividades y abrir el formulario de creación.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Consulta permisos efectivos y refleja las instancias confirmadas por la API.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import SortableHeader from '../components/common/SortableHeader'
import ExportButton from '../components/common/ExportButton'
import { recursoRequest } from '../services/recursosService'
import { assignmentView, assignmentsExportTable, assignmentAttendanceText, mergeAssignmentCatalogs, mergeAssignmentSnapshot } from '../utils/assignmentsExport'
import { useListSort } from '../hooks/useListSort'
import LoadingIndicator from '../components/LoadingIndicator'
import { clearReadCache } from '../services/readCache'

import { useEffect, useMemo, useState } from 'react'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import AsignacionCreateForm from '../components/asignaciones/DeferredAsignacionForm'
import { useConfirmation } from '../hooks/useConfirmation'
import { createAsignacion, getAsignacionesResumen, getOpcionesCreacion } from '../services/asignacionesService'
import type { AsignacionItem, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion } from '../types/asignaciones'
import '../styles/asignaciones.css'
import { colegiosDisponibles } from '../utils/asignacionesListado'
import { useAuth } from '../contexts/AuthContext'

const messageOf = (cause: unknown) => cause instanceof Error ? cause.message : 'No fue posible completar la operación.'

export default function AsignacionesPage() {
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const directCreate = params.get('crear') === '1'
  const initialDate = params.get('fecha') || ''
  const { user } = useAuth()
  const [items, setItems] = useState<AsignacionItem[]>([])
  const [catalogos, setCatalogos] = useState<CatalogosAsignacion | null>(null)
  const [permissions, setPermissions] = useState<string[]>([])
  const [loading, setLoading] = useState(true)
  const [exportBusy, setExportBusy] = useState(false)
  const [revision, setRevision] = useState(0)
  const [error, setError] = useState('')
  const [creationError, setCreationError] = useState('')
  const [catalogError, setCatalogError] = useState('')
  const { confirm, confirmationDialog } = useConfirmation()
  const [creating, setCreating] = useState(directCreate)
  const [loadingOptions, setLoadingOptions] = useState(directCreate)
  const [opciones, setOpciones] = useState<OpcionesCreacion | null>(null)
  const [search, setSearch] = useState('')
  const [tipoId, setTipoId] = useState('')
  const [estadoId, setEstadoId] = useState('')
  const [colegioId, setColegioId] = useState('')
  const [coordinadorId, setCoordinadorId] = useState('')
  const [monitorId, setMonitorId] = useState('')
  const [cursoId, setCursoId] = useState('')
  const [desde, setDesde] = useState(params.get('desde') || '')
  const [upcomingOnly, setUpcomingOnly] = useState(params.get('proximas') === '1')
  const [hasta, setHasta] = useState('')
  const sorting = useListSort<string>('fecha')
  const canCreate = permissions.includes('CREATE_ASSIGNMENT')
  useVisibleRefresh(async (isActive) => {
    try {
      const data = await getAsignacionesResumen(true)
      if (!isActive()) return
      setItems(data.items); setCatalogos(data.catalogos); setPermissions(data.permissions); setColegioId(previous => colegiosDisponibles(data.catalogos.colegios).some(school => school.id === previous) ? previous : '')
      setError('')
    } catch { /* Una falla temporal conserva el listado; el siguiente ciclo reintenta. */ }
  }, !loading && !creating && !loadingOptions && !exportBusy)
  useEffect(() => {
    if (!directCreate) return
    let active = true
    setCreating(true)
    setLoadingOptions(true)
    setCreationError('')
    void getOpcionesCreacion().then((data) => {
      if (!active) return
      if (!data.tipos_actividad.length) throw new Error('No hay tipos de actividad disponibles para tus permisos.')
      setOpciones(data)
    }).catch((cause: unknown) => {
      if (active) setCreationError(messageOf(cause))
    }).finally(() => {
      if (active) setLoadingOptions(false)
    })
    return () => { active = false }
  }, [directCreate])

  useEffect(() => {
    let active = true
    void getAsignacionesResumen().then((data) => {
      if (!active) return
      setItems(data.items); setCatalogos(data.catalogos); setPermissions(data.permissions); setColegioId(previous => colegiosDisponibles(data.catalogos.colegios).some(school => school.id === previous) ? previous : '')
      setError(''); setCatalogError(''); setLoading(false)
      if (revision === 0) setEstadoId(data.catalogos.estados.find(e => e.codigo === params.get('estado'))?.id || '')
    }).catch((cause: unknown) => { if (active) { setError(messageOf(cause)); setPermissions([]); setLoading(false) } })
    return () => { active = false }
  }, [revision, params])

  const tipos = useMemo(() => new Map(catalogos?.tipos_actividad.map((item) => [item.id, item]) ?? []), [catalogos])
  const estados = useMemo(() => new Map(catalogos?.estados.map((item) => [item.id, item]) ?? []), [catalogos])
  const colegios = useMemo(() => new Map(catalogos?.colegios.map((item) => [item.id, item.nombre]) ?? []), [catalogos])
  const colegiosFiltro = useMemo(() => colegiosDisponibles(catalogos?.colegios ?? []), [catalogos])
  const coordinadoresFiltro = useMemo(() => {
    const map = new Map<string, string>()
    items.flatMap((item) => item.coordinadores ?? []).forEach((person) => map.set(person.id, person.nombre))
    return [...map.entries()].map(([id, nombre]) => ({ id, nombre })).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-CL'))
  }, [items])
  const monitoresFiltro = useMemo(() => {
    const map = new Map<string, string>()
    items.flatMap((item) => item.monitores ?? []).forEach((person) => map.set(person.id, person.nombre))
    return [...map.entries()].map(([id, nombre]) => ({ id, nombre })).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-CL'))
  }, [items])
  const cursosFiltro = useMemo(() => {
    const map = new Map<string, string>()
    items.forEach((item) => { if (item.curso_colegio_id && item.curso_nombre) map.set(item.curso_colegio_id, item.curso_nombre) })
    return [...map.entries()].map(([id, nombre]) => ({ id, nombre })).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-CL'))
  }, [items])
  const isDirectiva = user?.role_code === 'DIRECTIVA'
  const isCoordinador = user?.role_code === 'COORDINADOR'
  const rangoInvalido = !!desde && !!hasta && desde > hasta
  const filters = { search, tipoId, estadoId, colegioId, coordinadorId, monitorId, cursoId, desde, hasta, upcomingOnly }
  const { filtered, ordered } = assignmentView(items, catalogos, filters, sorting.sort)

  async function prepareExport() {
    const query = new URLSearchParams()
    if (tipoId) query.set('tipo_actividad_id', tipoId)
    if (colegioId) query.set('colegio_id', colegioId)
    if (coordinadorId) query.set('coordinador_id', coordinadorId)
    if (monitorId) query.set('monitor_id', monitorId)
    if (cursoId) query.set('curso_colegio_id', cursoId)
    if (estadoId && estadoId !== 'POR_REASIGNAR') query.set('estado_id', estadoId)
    if (desde) query.set('fecha_desde', desde)
    if (hasta) query.set('fecha_hasta', hasta)
    const snapshot = await recursoRequest<{ items: AsignacionItem[]; catalogos: CatalogosAsignacion; total: number; generated_at: string }>(`/exports/assignments?${query}`, 'GET', undefined, true)
    if (snapshot.total !== snapshot.items.length) throw new Error('La consulta no está completa. Vuelve a intentarlo.')
    const freshCatalogs = mergeAssignmentCatalogs(catalogos, snapshot.catalogos)
    setItems(previous => mergeAssignmentSnapshot(previous, snapshot.items, filters)); setCatalogos(freshCatalogs)
    return assignmentsExportTable(snapshot.items, freshCatalogs, filters, sorting.sort, snapshot.generated_at, isDirectiva)
  }

  /** Carga opciones nuevas al abrir: un recurso eliminado no queda como opción cacheada. */
  async function openCreate() {
    if (!canCreate || loadingOptions) return
    setLoadingOptions(true)
    setCreationError('')
    try {
      const data = await getOpcionesCreacion()
      if (!data.tipos_actividad.length) throw new Error('No hay tipos de actividad disponibles para tus permisos.')
      setOpciones(data)
      setCreating(true)
    } catch (cause) { setCreationError(messageOf(cause)) }
    finally { setLoadingOptions(false) }
  }

  /** Guarda la instancia y actualiza el listado con la respuesta confirmada de la API. */
  async function save(payload: AsignacionPayload) {
    const created = await createAsignacion(payload)
    const asignados = payload.participantes.map((participant) => {
      const user = opciones?.participantes.find((person) => person.id === participant.usuario_id)
      return user ? [user.nombres, user.apellido_paterno, user.apellido_materno].filter(Boolean).join(' ') : 'Participante no disponible'
    })
    setItems((previous) => [...previous, { ...created, asignados_a: asignados }])
    setSearch(''); setTipoId(''); setEstadoId(''); setColegioId(''); setCoordinadorId(''); setMonitorId(''); setCursoId(''); setDesde(''); setHasta('')
    setCreating(false)
    await confirm({
      title: 'Instancia creada',
      message: 'La instancia y sus participantes quedaron registrados.',
      confirmLabel: 'Entendido',
      acknowledgeOnly: true,
      variant: 'success',
    })
    if (directCreate) navigate('/app/asignaciones', { replace: true })
    return created
  }

  /** Invalida lecturas previas y vuelve a consultar el resumen y sus catálogos. */
  function refresh() { clearReadCache(); setLoading(true); setError(''); setRevision((value) => value + 1) }

  if (directCreate) {
    return <section className="assignments-page">
      {confirmationDialog}
      {creationError && <p className="assignments-error" role="alert">{creationError}</p>}
      {loadingOptions || !opciones
        ? <LoadingIndicator />
        : <AsignacionCreateForm
            opciones={opciones}
            onCreate={save}
            onClose={() => navigate('/app/asignaciones')}
            initialDate={initialDate}
          />}
    </section>
  }

  return <section className="assignments-page">
    {confirmationDialog}
    <header className="assignments-heading"><div><h1>Instancias</h1><p>Organiza actividades, establecimientos y participantes.</p></div>
      {canCreate && !creating && <button type="button" className="assignments-primary" disabled={loading || loadingOptions || exportBusy || !!error} onClick={() => void openCreate()}>{loadingOptions ? 'Cargando opciones…' : '+ Crear instancia'}</button>}
    </header>
    {creationError && <p className="assignments-error" role="alert">{creationError}</p>}
    {creating && opciones ? <AsignacionCreateForm opciones={opciones} onCreate={save} onClose={() => setCreating(false)} /> : <div className="assignments-panel">
      <div className="assignments-panel-heading"><div><h2>Actividades registradas</h2><p>{loading ? 'Cargando…' : `${filtered.length} de ${items.length} instancias`}</p></div>
        <div className="query-table-actions">
          <button type="button" className="assignments-secondary assignments-export-refresh" disabled={loading || loadingOptions || exportBusy} onClick={refresh}>Actualizar</button>
          <ExportButton disabled={loading || loadingOptions || !!error || rangoInvalido || !filtered.length} prepare={prepareExport} onBusyChange={setExportBusy} />
        </div>
      </div>
      {catalogError && <p className="assignments-warning" role="alert">{catalogError}</p>}
      <div className="assignments-filters" inert={exportBusy}>
        {upcomingOnly && <label><input type="checkbox" checked={upcomingOnly} onChange={e => setUpcomingOnly(e.target.checked)} /> Solo próximas actividades</label>}
        <label>Buscar<input type="search" placeholder="Actividad, persona, colegio o curso…" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
        <label>Tipo de actividad<select value={tipoId} onChange={(event) => setTipoId(event.target.value)}><option value="">Todos los tipos</option>{catalogos?.tipos_actividad.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Estado<select value={estadoId} onChange={(event) => setEstadoId(event.target.value)}><option value="">Todos los estados</option><option value="POR_REASIGNAR">Por reasignar</option>{catalogos?.estados.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Colegio<select value={colegioId} onChange={(event) => setColegioId(event.target.value)}><option value="">Todos los colegios</option>{colegiosFiltro.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        {isDirectiva && <label>Coordinador<select value={coordinadorId} onChange={(event) => setCoordinadorId(event.target.value)}><option value="">Todos los coordinadores</option>{coordinadoresFiltro.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>}
        {(isDirectiva || isCoordinador) && <label>Monitor<select value={monitorId} onChange={(event) => setMonitorId(event.target.value)}><option value="">Todos los monitores</option>{monitoresFiltro.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>}
        {(isDirectiva || isCoordinador) && <label>Curso<select value={cursoId} onChange={(event) => setCursoId(event.target.value)}><option value="">Todos los cursos</option>{cursosFiltro.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>}
        <label>Desde<input type="date" value={desde} onChange={(event) => setDesde(event.target.value)} /></label>
        <label>Hasta<input type="date" value={hasta} onChange={(event) => setHasta(event.target.value)} /></label>
      </div>
      {rangoInvalido && <p className="assignments-error" role="alert">La fecha desde debe ser anterior o igual a la fecha hasta.</p>}
      {loading ? <LoadingIndicator /> : error ? <div className="assignments-feedback" role="alert"><p>{error}</p><button type="button" className="assignments-secondary" onClick={refresh}>Reintentar</button></div>
        : !filtered.length ? <p className="assignments-feedback">{items.length ? 'No hay instancias que coincidan con los filtros.' : 'Aún no hay instancias registradas.'}</p>
          : <div className="assignments-table-scroll" inert={exportBusy}><table className="assignments-table"><thead><tr><SortableHeader label="Actividad" column="actividad" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Colegio / Lugar" column="colegio" sort={sorting.sort} onSort={sorting.toggle} />{isDirectiva && <SortableHeader label="Coordinador" column="coordinadores" sort={sorting.sort} onSort={sorting.toggle} />}<SortableHeader label="Monitor" column="monitores" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Fecha" column="fecha" sort={sorting.sort} onSort={sorting.toggle} /><th scope="col">Horario</th><th scope="col">Estado</th><th scope="col">Asistencia</th><th scope="col">Acciones</th></tr></thead>
            <tbody>{ordered.map((item) => <tr key={item.id}>
              <td className="assignments-name">{tipos.get(item.tipo_actividad_id)?.nombre ?? 'Actividad'}</td>
              <td>{item.colegio_id ? colegios.get(item.colegio_id) ?? 'Colegio no disponible' : item.lugar || '—'}</td>
              {isDirectiva && <td><ul className="assignments-assignees">{item.coordinadores?.length ? item.coordinadores.map((person) => <li key={person.id}>{person.nombre}</li>) : <li>Sin coordinador asociado</li>}</ul></td>}
              <td><ul className="assignments-assignees">{item.monitores?.length ? item.monitores.map((person) => <li key={person.id}>{person.nombre}</li>) : <li>Sin monitor</li>}</ul></td>
              <td>{item.fecha.split('-').reverse().join('/')}</td><td>{item.hora_inicio.slice(0, 5)} – {item.hora_fin.slice(0, 5)}</td>
              <td><span className={`assignments-status assignments-status--${item.por_reasignar ? 'por_reasignar' : estados.get(item.estado_id)?.codigo.toLowerCase() ?? 'unknown'}`}>{item.por_reasignar ? 'Por reasignar' : estados.get(item.estado_id)?.nombre ?? 'Estado no disponible'}</span></td>
              <td><Link className="assignments-action" to={`/app/asistencia?asignacion=${item.id}`}>{assignmentAttendanceText(item)}</Link></td>
              <td><Link className="assignments-action assignments-detail-button" to={`/app/asignaciones/${item.id}`}>Ver detalle</Link></td>
            </tr>)}</tbody></table></div>}
    </div>}
  </section>
}
