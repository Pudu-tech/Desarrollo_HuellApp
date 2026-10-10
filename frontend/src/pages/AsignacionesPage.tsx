import LoadingIndicator from '../components/LoadingIndicator'
import { clearReadCache } from '../services/readCache'
/**
 * HuellApp · Listado y creación de asignaciones para roles de gestión.
 * Mantiene la presentación de Usuarios/Colegios y consulta permisos efectivos.
 * Las altas se confirman en backend y actualizan inmediatamente el listado.
 */
import { useEffect, useMemo, useState } from 'react'
import { useVisibleRefresh } from '../hooks/useVisibleRefresh'
import { Link } from 'react-router-dom'
import AsignacionCreateForm from '../components/asignaciones/DeferredAsignacionForm'
import { createAsignacion, getAsignacionesResumen, getOpcionesCreacion } from '../services/asignacionesService'
import type { AsignacionItem, AsignacionPayload, CatalogosAsignacion, OpcionesCreacion } from '../types/asignaciones'
import '../styles/asignaciones.css'

const messageOf = (cause: unknown) => cause instanceof Error ? cause.message : 'No fue posible completar la operación.'

export default function AsignacionesPage() {
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
  const [desde, setDesde] = useState('')
  const [hasta, setHasta] = useState('')
  const canCreate = permissions.includes('CREATE_ASSIGNMENT')
  useVisibleRefresh(async (isActive) => {
    try {
      const data = await getAsignacionesResumen(true)
      if (!isActive()) return
      setItems(data.items); setCatalogos(data.catalogos); setPermissions(data.permissions)
      setError('')
    } catch { /* Una falla temporal conserva el listado; el siguiente ciclo reintenta. */ }
  }, !loading && !creating && !loadingOptions)
  useEffect(() => {
    let active = true
    void getAsignacionesResumen().then((data) => {
      if (!active) return
      setItems(data.items); setCatalogos(data.catalogos); setPermissions(data.permissions)
      setError(''); setCatalogError(''); setLoading(false)
    }).catch((cause: unknown) => { if (active) { setError(messageOf(cause)); setPermissions([]); setLoading(false) } })
    return () => { active = false }
  }, [revision])

  const tipos = useMemo(() => new Map(catalogos?.tipos_actividad.map((item) => [item.id, item]) ?? []), [catalogos])
  const estados = useMemo(() => new Map(catalogos?.estados.map((item) => [item.id, item]) ?? []), [catalogos])
  const colegios = useMemo(() => new Map(catalogos?.colegios.map((item) => [item.id, item.nombre]) ?? []), [catalogos])
  const rangoInvalido = !!desde && !!hasta && desde > hasta
  const filtered = useMemo(() => items.filter((item) => {
    if (tipoId && item.tipo_actividad_id !== tipoId) return false
    if (estadoId === 'POR_REASIGNAR' ? !item.por_reasignar : estadoId && (item.estado_id !== estadoId || item.por_reasignar)) return false
    if (colegioId && item.colegio_id !== colegioId) return false
    if (desde && item.fecha < desde) return false
    if (hasta && item.fecha > hasta) return false
    const text = `${tipos.get(item.tipo_actividad_id)?.nombre ?? ''} ${colegios.get(item.colegio_id ?? '') ?? ''} ${item.lugar ?? ''} ${item.observacion ?? ''}`
    return text.toLocaleLowerCase('es-CL').includes(search.trim().toLocaleLowerCase('es-CL'))
  }), [items, tipoId, estadoId, colegioId, desde, hasta, search, tipos, colegios])

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

  async function save(payload: AsignacionPayload) {
    const created = await createAsignacion(payload)
    setItems((previous) => [...previous, created].sort((a, b) => `${a.fecha}${a.hora_inicio}`.localeCompare(`${b.fecha}${b.hora_inicio}`)))
    setSearch(''); setTipoId(''); setEstadoId(''); setColegioId(''); setDesde(''); setHasta('')
    setCreating(false)
    setNotice('Asignación creada correctamente. Participantes, contactos y auditoría quedaron registrados.')
    return created
  }

  function refresh() { clearReadCache(); setLoading(true); setError(''); setRevision((value) => value + 1) }

  return <section className="assignments-page">
    <header className="assignments-heading"><div><h1>Asignaciones</h1><p>Organiza actividades, establecimientos y participantes.</p></div>
      {canCreate && !creating && <button type="button" className="assignments-primary" disabled={loading || loadingOptions || !!error} onClick={() => void openCreate()}>{loadingOptions ? 'Cargando opciones…' : '+ Crear asignación'}</button>}
    </header>
    {notice && <p className="assignments-success" role="status">{notice}</p>}
    {creationError && <p className="assignments-error" role="alert">{creationError}</p>}
    {creating && opciones ? <AsignacionCreateForm opciones={opciones} onCreate={save} onClose={() => setCreating(false)} /> : <div className="assignments-panel">
      <div className="assignments-panel-heading"><div><h2>Actividades registradas</h2><p>{loading ? 'Cargando…' : `${filtered.length} de ${items.length} asignaciones`}</p></div>
        <button type="button" className="assignments-secondary" disabled={loading || loadingOptions} onClick={refresh}>Actualizar</button>
      </div>
      {catalogError && <p className="assignments-warning" role="alert">{catalogError}</p>}
      <div className="assignments-filters">
        <label>Buscar<input type="search" placeholder="Actividad, colegio o lugar…" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
        <label>Tipo de actividad<select value={tipoId} onChange={(event) => setTipoId(event.target.value)}><option value="">Todos los tipos</option>{catalogos?.tipos_actividad.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Estado<select value={estadoId} onChange={(event) => setEstadoId(event.target.value)}><option value="">Todos los estados</option><option value="POR_REASIGNAR">Por reasignar</option>{catalogos?.estados.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Colegio<select value={colegioId} onChange={(event) => setColegioId(event.target.value)}><option value="">Todos los colegios</option>{catalogos?.colegios.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}</select></label>
        <label>Desde<input type="date" value={desde} onChange={(event) => setDesde(event.target.value)} /></label>
        <label>Hasta<input type="date" value={hasta} onChange={(event) => setHasta(event.target.value)} /></label>
      </div>
      {rangoInvalido && <p className="assignments-error" role="alert">La fecha desde debe ser anterior o igual a la fecha hasta.</p>}
      {loading ? <LoadingIndicator /> : error ? <div className="assignments-feedback" role="alert"><p>{error}</p><button type="button" className="assignments-secondary" onClick={refresh}>Reintentar</button></div>
        : !filtered.length ? <p className="assignments-feedback">{items.length ? 'No hay asignaciones que coincidan con los filtros.' : 'Aún no hay asignaciones registradas.'}</p>
          : <div className="assignments-table-scroll"><table className="assignments-table"><thead><tr><th scope="col">Actividad</th><th scope="col">Colegio / Lugar</th><th scope="col">Fecha</th><th scope="col">Horario</th><th scope="col">Estado</th><th scope="col">Asistencia</th><th scope="col">Acciones</th></tr></thead>
            <tbody>{filtered.map((item) => <tr key={item.id}>
              <td className="assignments-name">{tipos.get(item.tipo_actividad_id)?.nombre ?? 'Actividad'}</td>
              <td>{item.colegio_id ? colegios.get(item.colegio_id) ?? 'Colegio no disponible' : item.lugar || '—'}</td>
              <td>{item.fecha.split('-').reverse().join('/')}</td><td>{item.hora_inicio.slice(0, 5)} – {item.hora_fin.slice(0, 5)}</td>
              <td><span className={`assignments-status assignments-status--${item.por_reasignar ? 'por_reasignar' : estados.get(item.estado_id)?.codigo.toLowerCase() ?? 'unknown'}`}>{item.por_reasignar ? 'Por reasignar' : estados.get(item.estado_id)?.nombre ?? 'Estado no disponible'}</span></td>
              <td><Link className="assignments-action" to={`/app/asistencia?asignacion=${item.id}`}>{Object.entries(item.asistencia_resumen ?? {}).filter(([, count]) => count > 0).map(([state, count]) => `${count} ${state === 'NO_REQUERIDA' ? 'no requerida' : state.toLowerCase()}`).join(' · ') || 'Sin registros'}</Link></td>
              <td><Link className="assignments-action" to={`/app/asignaciones/${item.id}`}>Ver detalle</Link></td>
            </tr>)}</tbody></table></div>}
    </div>}
  </section>
}
