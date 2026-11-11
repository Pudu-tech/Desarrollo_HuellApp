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
import { useListSort } from '../hooks/useListSort'
import LoadingIndicator from '../components/LoadingIndicator'
import { clearReadCache } from '../services/readCache'

import { useEffect, useMemo, useState } from 'react'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import { Link, useSearchParams } from 'react-router-dom'
import AsignacionCreateForm from '../components/asignaciones/DeferredAsignacionForm'
import { createAsignacion, getAsignacionesResumen, getOpcionesCreacion } from '../services/asignacionesService'
import type { AsignacionItem, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion } from '../types/asignaciones'
import '../styles/asignaciones.css'
import { colegiosDisponibles } from '../utils/asignacionesListado'

const messageOf = (cause: unknown) => cause instanceof Error ? cause.message : 'No fue posible completar la operación.'

export default function AsignacionesPage() {
  const [params] = useSearchParams()
  const [items, setItems] = useState<AsignacionItem[]>([])
  const [catalogos, setCatalogos] = useState<CatalogosAsignacion | null>(null)
  const [permissions, setPermissions] = useState<string[]>([])
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [error, setError] = useState('')
  const [creationError, setCreationError] = useState('')
  const [catalogError, setCatalogError] = useState('')
  const [notice, setNotice] = useState('')
  const [creating, setCreating] = useState(false)
  const [loadingOptions, setLoadingOptions] = useState(false)
  const [opciones, setOpciones] = useState<OpcionesCreacion | null>(null)
  const [search, setSearch] = useState('')
  const [tipoId, setTipoId] = useState('')
  const [estadoId, setEstadoId] = useState('')
  const [colegioId, setColegioId] = useState('')
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
  }, !loading && !creating && !loadingOptions)
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
  const rangoInvalido = !!desde && !!hasta && desde > hasta
  const filtered = useMemo(() => items.filter((item) => {
    if (upcomingOnly && ['REALIZADA', 'CANCELADA', 'NO_REALIZADA'].includes(estados.get(item.estado_id)?.codigo || '')) return false
    if (tipoId && item.tipo_actividad_id !== tipoId) return false
    if (estadoId === 'POR_REASIGNAR' ? !item.por_reasignar : estadoId && (item.estado_id !== estadoId || item.por_reasignar)) return false
    if (colegioId && item.colegio_id !== colegioId) return false
    if (desde && item.fecha < desde) return false
    if (hasta && item.fecha > hasta) return false
    const text = `${tipos.get(item.tipo_actividad_id)?.nombre ?? ''} ${colegios.get(item.colegio_id ?? '') ?? ''} ${item.lugar ?? ''} ${item.observacion ?? ''}`
    return text.toLocaleLowerCase('es-CL').includes(search.trim().toLocaleLowerCase('es-CL'))
  }), [items, tipoId, estadoId, colegioId, desde, hasta, search, tipos, colegios, upcomingOnly, estados])
  const ordered = sorting.order(filtered, { fecha: r => `${r.fecha} ${r.hora_inicio}`, actividad: r => tipos.get(r.tipo_actividad_id)?.nombre, colegio: r => colegios.get(r.colegio_id ?? '') ?? r.lugar, participantes: r => r.asignados_a?.join(', ') })

  /** Carga opciones nuevas al abrir: un recurso eliminado no queda como opción cacheada. */
  async function openCreate() {
    if (!canCreate || loadingOptions) return
    setLoadingOptions(true)
    setCreationError('')
    setNotice('')
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
    setSearch(''); setTipoId(''); setEstadoId(''); setColegioId(''); setDesde(''); setHasta('')
    setCreating(false)
    setNotice('Instancia creada correctamente. Participantes, contactos y auditoría quedaron registrados.')
    return created
  }

  /** Invalida lecturas previas y vuelve a consultar el resumen y sus catálogos. */
  function refresh() { clearReadCache(); setLoading(true); setError(''); setRevision((value) => value + 1) }

  return <section className="assignments-page">
    <header className="assignments-heading"><div><h1>Instancias</h1><p>Organiza actividades, establecimientos y participantes.</p></div>
      {canCreate && !creating && <button type="button" className="assignments-primary" disabled={loading || loadingOptions || !!error} onClick={() => void openCreate()}>{loadingOptions ? 'Cargando opciones…' : '+ Crear instancia'}</button>}
    </header>
    {notice && <p className="assignments-success" role="status">{notice}</p>}
    {creationError && <p className="assignments-error" role="alert">{creationError}</p>}
    {creating && opciones ? <AsignacionCreateForm opciones={opciones} onCreate={save} onClose={() => setCreating(false)} /> : <div className="assignments-panel">
      <div className="assignments-panel-heading"><div><h2>Actividades registradas</h2><p>{loading ? 'Cargando…' : `${filtered.length} de ${items.length} instancias`}</p></div>
        <button type="button" className="assignments-secondary" disabled={loading || loadingOptions} onClick={refresh}>Actualizar</button>
      </div>
      {catalogError && <p className="assignments-warning" role="alert">{catalogError}</p>}
      <div className="assignments-filters">
        {upcomingOnly && <label><input type="checkbox" checked={upcomingOnly} onChange={e => setUpcomingOnly(e.target.checked)} /> Solo próximas actividades</label>}
        <label>Buscar<input type="search" placeholder="Actividad, colegio o lugar…" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
        <label>Tipo de actividad<select value={tipoId} onChange={(event) => setTipoId(event.target.value)}><option value="">Todos los tipos</option>{catalogos?.tipos_actividad.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Estado<select value={estadoId} onChange={(event) => setEstadoId(event.target.value)}><option value="">Todos los estados</option><option value="POR_REASIGNAR">Por reasignar</option>{catalogos?.estados.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Colegio<select value={colegioId} onChange={(event) => setColegioId(event.target.value)}><option value="">Todos los colegios</option>{colegiosFiltro.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Desde<input type="date" value={desde} onChange={(event) => setDesde(event.target.value)} /></label>
        <label>Hasta<input type="date" value={hasta} onChange={(event) => setHasta(event.target.value)} /></label>
      </div>
      {rangoInvalido && <p className="assignments-error" role="alert">La fecha desde debe ser anterior o igual a la fecha hasta.</p>}
      {loading ? <LoadingIndicator /> : error ? <div className="assignments-feedback" role="alert"><p>{error}</p><button type="button" className="assignments-secondary" onClick={refresh}>Reintentar</button></div>
        : !filtered.length ? <p className="assignments-feedback">{items.length ? 'No hay instancias que coincidan con los filtros.' : 'Aún no hay instancias registradas.'}</p>
          : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><SortableHeader label="Actividad" column="actividad" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Colegio / Lugar" column="colegio" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Asignada a" column="participantes" sort={sorting.sort} onSort={sorting.toggle} /><SortableHeader label="Fecha" column="fecha" sort={sorting.sort} onSort={sorting.toggle} /><th scope="col">Horario</th><th scope="col">Estado</th><th scope="col">Asistencia</th><th scope="col">Acciones</th></tr></thead>
            <tbody>{ordered.map((item) => <tr key={item.id}>
              <td className="assignments-name">{tipos.get(item.tipo_actividad_id)?.nombre ?? 'Actividad'}</td>
              <td>{item.colegio_id ? colegios.get(item.colegio_id) ?? 'Colegio no disponible' : item.lugar || '—'}</td>
              <td><ul className="assignments-assignees">{item.asignados_a?.length ? item.asignados_a.map((name, index) => <li key={`${index}-${name}`}>{name}</li>) : <li>Sin participantes</li>}</ul></td>
              <td>{item.fecha.split('-').reverse().join('/')}</td><td>{item.hora_inicio.slice(0, 5)} – {item.hora_fin.slice(0, 5)}</td>
              <td><span className={`assignments-status assignments-status--${item.por_reasignar ? 'por_reasignar' : estados.get(item.estado_id)?.codigo.toLowerCase() ?? 'unknown'}`}>{item.por_reasignar ? 'Por reasignar' : estados.get(item.estado_id)?.nombre ?? 'Estado no disponible'}</span></td>
              <td><Link className="assignments-action" to={`/app/asistencia?asignacion=${item.id}`}>{Object.entries(item.asistencia_resumen ?? {}).filter(([, count]) => count > 0).map(([state, count]) => `${count} ${state === 'NO_REQUERIDA' ? 'no requerida' : state.toLowerCase()}`).join(' · ') || 'Sin registros'}</Link></td>
              <td><Link className="assignments-action assignments-detail-button" to={`/app/asignaciones/${item.id}`}>Ver detalle</Link></td>
            </tr>)}</tbody></table></div>}
    </div>}
  </section>
}
