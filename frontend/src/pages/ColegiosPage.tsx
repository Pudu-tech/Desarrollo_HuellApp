/**
 * HuellApp · Mantenedor de colegios.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Listar colegios y filtrar por nombre/RBD, región, comuna y estado.
 * - Crear colegios, abrir la edición y reflejar las respuestas del backend.
 * - Mostrar catálogos cargados desde la API, sin datos fijos.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Ficha con Información, Contactos, Cursos y Salas del colegio seleccionado.
 * - Eliminación lógica en cascada confirmada disponible solo para SUPERADMIN.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La visibilidad de acciones es solo presentación; FastAPI valida permisos.
 */

import { useEffect, useMemo, useState } from 'react'
import ColegioEditForm from '../components/colegios/ColegioEditForm'
import ColegioCreateForm from '../components/colegios/ColegioCreateForm'
import ColegioDeleteDialog from '../components/colegios/ColegioDeleteDialog'
import { useAuth } from '../contexts/AuthContext'
import {
  activateColegio,
  createColegio,
  deactivateColegio,
  deleteColegio,
  updateColegio,
  getColegios,
  getComunas,
  getRegiones,
  getTiposDependencia,
} from '../services/colegiosService'
import type {
  ColegioCreatePayload,
  ColegioListItem,
  ComunaItem,
  RegionItem,
  TipoDependenciaItem,
} from '../types/colegios'
import '../styles/colegios.css'

/**
 * Normaliza errores desconocidos para mostrar un mensaje comprensible.
 */
function getErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Ocurrió un error inesperado.'
}

/**
 * Presenta el listado y coordina filtros, catálogos y edición.
 * Los cambios persistentes se delegan al servicio y al backend.
 */
function ColegiosPage() {
  const { user } = useAuth()
  const canManage = user?.role_code === 'SUPERADMIN' || user?.role_code === 'DIRECTIVA'
  const canDelete = user?.role_code === 'SUPERADMIN'
  const [editing, setEditing] = useState<ColegioListItem | null>(null)
  const [creating, setCreating] = useState(false)
  const [pendingDelete, setPendingDelete] = useState<ColegioListItem | null>(null)
  const [deleting, setDeleting] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [colegios, setColegios] = useState<ColegioListItem[]>([])
  const [regiones, setRegiones] = useState<RegionItem[]>([])
  const [comunas, setComunas] = useState<ComunaItem[]>([])
  const [dependencias, setDependencias] = useState<TipoDependenciaItem[]>([])
  const [loading, setLoading] = useState(true)
  const [catalogError, setCatalogError] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [comunasError, setComunasError] = useState<string | null>(null)
  const [loadingComunas, setLoadingComunas] = useState(false)
  const [search, setSearch] = useState('')
  const [regionId, setRegionId] = useState('')
  const [comunaId, setComunaId] = useState('')
  const [estado, setEstado] = useState('todos')

/**
 * Carga colegios y catálogos en paralelo sin ocultar errores parciales.
 */
  const loadData = async () => {
    const [schools, regions, types] = await Promise.allSettled([
      getColegios(), getRegiones(), getTiposDependencia(),
    ])
    if (schools.status === 'fulfilled') {
      setColegios(schools.value)
    } else {
      setError(getErrorMessage(schools.reason))
    }
    if (regions.status === 'fulfilled') setRegiones(regions.value)
    if (types.status === 'fulfilled') setDependencias(types.value)
    if (regions.status === 'rejected' || types.status === 'rejected') {
      setCatalogError('No se pudieron cargar todos los catálogos. Reintenta para recuperar los filtros.')
    }
    setLoading(false)
  }

  /** La recarga explícita restablece los mensajes fuera del efecto inicial. */
  const refreshData = () => {
    setLoading(true)
    setError(null)
    setCatalogError(null)
    void loadData()
  }

  useEffect(() => {
    // Inicia la carga como resultado asíncrono y evita la petición del montaje
    // descartado por StrictMode, sin disparar cambios de estado en el efecto.
    let active = true
    void Promise.resolve().then(() => { if (active) return loadData() })
    return () => { active = false }
  }, [])

  // Cada cambio de región recarga sus comunas y descarta respuestas obsoletas.
  useEffect(() => {
    if (!regionId) {
      return
    }
    let active = true
    void getComunas(regionId)
      .then((result) => {
        if (active) setComunas(result)
      })
      .catch((loadError: unknown) => {
        if (active) setComunasError(getErrorMessage(loadError))
      })
      .finally(() => {
        if (active) setLoadingComunas(false)
      })
    return () => { active = false }
  }, [regionId])

  // El filtrado es local sobre los colegios ya recibidos del backend.
  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase('es-CL')
    return colegios.filter((colegio) => {
      if (regionId && colegio.region_id !== regionId) return false
      if (comunaId && colegio.comuna_id !== comunaId) return false
      if (estado === 'activos' && !colegio.activo) return false
      if (estado === 'inactivos' && colegio.activo) return false
      if (!query) return true
      return colegio.nombre.toLocaleLowerCase('es-CL').includes(query)
        || (colegio.rbd ?? '').toLocaleLowerCase('es-CL').includes(query)
    })
  }, [colegios, search, regionId, comunaId, estado])

  const regionNames = useMemo(
    () => new Map(regiones.map((region) => [region.id, region.nombre])),
    [regiones],
  )
  const comunaNames = useMemo(
    () => new Map(comunas.map((comuna) => [comuna.id, comuna.nombre])),
    [comunas],
  )
  const dependenciaNames = useMemo(
    () => new Map(dependencias.map((dependencia) => [dependencia.id, dependencia.nombre])),
    [dependencias],
  )

/**
 * Persiste los campos editados y sincroniza listado y formulario.
 */
  /** Inserta el registro confirmado por POST y restablece filtros para mostrarlo. */
  const handleCreate = async (data: ColegioCreatePayload) => {
    const created = await createColegio(data)
    setColegios((current) => [...current, created].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es-CL')))
    setSearch('')
    setRegionId('')
    setComunaId('')
    setComunas([])
    setComunasError(null)
    setLoadingComunas(false)
    setEstado('todos')
    setCreating(false)
    // Los contactos requieren el UUID generado; abrir edición tras el alta.
    setEditing(created)
    return created
  }

  const handleSave = async (id: string, changes: Partial<Omit<ColegioListItem, 'id' | 'activo'>>) => {
    const updated = await updateColegio(id, changes)
    setColegios((current) => current.map((item) => item.id === id ? updated : item))
    setEditing(updated)
    return updated
  }

/**
 * Alterna activación/desactivación mediante endpoints independientes.
 */
  const handleToggle = async (colegio: ColegioListItem) => {
    const updated = colegio.activo
      ? await deactivateColegio(colegio.id)
      : await activateColegio(colegio.id)
    setColegios((current) => current.map((item) => item.id === updated.id ? updated : item))
    setEditing(updated)
    return updated
  }

  /**
   * Confirma la eliminación solicitada y actualiza únicamente el listado local.
   * El backend comprueba DELETE_SCHOOL y registra la auditoría en la base de datos.
   * En caso de error se conserva el colegio y se muestra el mensaje del servidor.
   */
  const confirmDelete = async () => {
    if (!pendingDelete || !canDelete || deleting) return
    setDeleting(true)
    setDeleteError(null)
    try {
      await deleteColegio(pendingDelete.id)
      setNotice(`Se eliminaron lógicamente «${pendingDelete.nombre}» y sus recursos asociados. El historial se conservó.`)
      setColegios((current) => current.filter((item) => item.id !== pendingDelete.id))
      if (editing?.id === pendingDelete.id) setEditing(null)
      setPendingDelete(null)
    } catch (deleteFailure) {
      setDeleteError(getErrorMessage(deleteFailure))
    } finally {
      setDeleting(false)
    }
  }

  /** Abre la confirmación sin realizar cambios hasta la aceptación explícita. */
  const requestDelete = (colegio: ColegioListItem) => {
    setDeleteError(null)
    setPendingDelete(colegio)
  }

  return (
    <section className="schools-page">
      <header className="schools-heading">
        <div>
          <h1>Colegios</h1>
          <p>Administración de establecimientos educacionales.</p>
        </div>
        {canManage && !creating && !editing && (
          <button className="schools-primary" type="button" onClick={() => { setNotice(null); setCreating(true) }} disabled={!regiones.length}>
            + Crear colegio
          </button>
        )}
      </header>
      {notice && <p className="schools-success" role="status">{notice}</p>}

      {creating ? (
        <ColegioCreateForm
          regiones={regiones}
          dependencias={dependencias}
          onCreate={handleCreate}
          onClose={() => setCreating(false)}
        />
      ) : editing ? (
        <ColegioEditForm
          key={editing.id}
          colegio={editing}
          regiones={regiones}
          dependencias={dependencias}
          onSave={handleSave}
          onToggleStatus={handleToggle}
          onRequestDelete={canDelete ? requestDelete : undefined}
          onClose={() => setEditing(null)}
        />
      ) : <div className="schools-panel">
        <div className="schools-panel-heading">
          <div>
            <h2>Establecimientos registrados</h2>
            <p>{loading ? 'Cargando...' : `${filtered.length} de ${colegios.length} colegios`}</p>
          </div>
          <button type="button" className="schools-secondary" onClick={refreshData} disabled={loading}>
            Actualizar
          </button>
        </div>

        {catalogError && <p className="schools-warning" role="alert">{catalogError}</p>}
        <div className="schools-filters">
          <label>
            Buscar por nombre o RBD
            <input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar colegio..." />
          </label>
          <label>
            Región
            <select value={regionId} onChange={(event) => {
              setRegionId(event.target.value)
              setComunaId('')
              setComunas([])
              setComunasError(null)
              setLoadingComunas(!!event.target.value)
            }}>
              <option value="">Todas las regiones</option>
              {regiones.map((region) => <option key={region.id} value={region.id}>{region.nombre}</option>)}
            </select>
          </label>
          <label>
            Comuna
            <select value={comunaId} onChange={(event) => setComunaId(event.target.value)} disabled={!regionId || loadingComunas || !!comunasError}>
              <option value="">{loadingComunas ? 'Cargando comunas...' : 'Todas las comunas'}</option>
              {comunas.map((comuna) => <option key={comuna.id} value={comuna.id}>{comuna.nombre}</option>)}
            </select>
          </label>
          <label>
            Estado
            <select value={estado} onChange={(event) => setEstado(event.target.value)}>
              <option value="todos">Todos</option>
              <option value="activos">Activos</option>
              <option value="inactivos">Inactivos</option>
            </select>
          </label>
        </div>
        {comunasError && <p className="schools-warning" role="alert">Error al cargar comunas: {comunasError}</p>}

        {loading ? (
          <p className="schools-feedback" role="status">Cargando establecimientos...</p>
        ) : error ? (
          <div className="schools-feedback" role="alert">
            <p>{error}</p>
            <button type="button" className="schools-secondary" onClick={refreshData}>Reintentar</button>
          </div>
        ) : filtered.length === 0 ? (
          <p className="schools-feedback">{colegios.length === 0 ? 'Todavía no hay colegios registrados.' : 'No hay colegios que coincidan con los filtros.'}</p>
        ) : (
          <div className="schools-table-scroll">
            <table className="schools-table">
              <thead>
                <tr>
                  <th scope="col">Colegio</th>
                  <th scope="col">RBD</th>
                  <th scope="col">Ubicación</th>
                  <th scope="col">Dependencia</th>
                  <th scope="col">Estado</th>
                  {canManage && <th scope="col">Acciones</th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map((colegio) => (
                  <tr key={colegio.id}>
                    <td className="schools-name">{colegio.nombre}</td>
                    <td>{colegio.rbd || '—'}</td>
                    <td>
                      {regionId && comunaNames.get(colegio.comuna_id)
                        ? `${comunaNames.get(colegio.comuna_id)}, ` : ''}
                      {regionNames.get(colegio.region_id) ?? 'Región no disponible'}
                    </td>
                    <td>{colegio.tipo_dependencia_id
                      ? dependenciaNames.get(colegio.tipo_dependencia_id) ?? 'No disponible'
                      : 'Sin especificar'}</td>
                    <td><span className={`schools-status ${colegio.activo ? 'schools-status--active' : 'schools-status--inactive'}`}>
                      {colegio.activo ? 'Activo' : 'Inactivo'}
                    </span></td>
                    {canManage && <td>
                      {/* La eliminación se ofrece únicamente al final de Editar colegio. */}
                      <button type="button" className="schools-action" onClick={() => { setNotice(null); setEditing(colegio) }}>
                        Editar
                      </button>
                    </td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>}
      {pendingDelete && <ColegioDeleteDialog colegio={pendingDelete} working={deleting} error={deleteError}
        onCancel={() => setPendingDelete(null)} onConfirm={() => void confirmDelete()} />}
    </section>
  )
}

export default ColegiosPage
