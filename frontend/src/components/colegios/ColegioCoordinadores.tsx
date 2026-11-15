/**
 * HuellApp · Coordinadores y monitores de un colegio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Mostrar los coordinadores asociados al establecimiento.
 * - Asignar y desasignar coordinadores sin crear usuarios duplicados.
 * - Advertir cuando una asignación multi-colegio es excepcional.
 * - Gestionar los monitores de cada coordinador dentro del colegio actual.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La UI respeta permisos para orientar al usuario. FastAPI y las RPC validan
 * nuevamente cada lectura y escritura.
 */

import { useEffect, useMemo, useState } from 'react'
import {
  MultiSchoolAssignmentError,
  assignCoordinatorMonitor,
  assignSchoolCoordinator,
  getCoordinatorCandidates,
  getCoordinatorMonitors,
  getMonitorCandidates,
  getSchoolCoordinators,
  unassignCoordinatorMonitor,
  unassignSchoolCoordinator,
} from '../../services/coordinacionService'
import type {
  CoordinadorColegioItem,
  MonitorCoordinadorItem,
  MultiSchoolConflictDetail,
  UsuarioCoordinacionItem,
} from '../../types/coordinacion'
import LoadingIndicator from '../LoadingIndicator'
import { useConfirmation } from '../../hooks/useConfirmation'

interface Props {
  colegioId: string
  colegioNombre: string
  colegioActivo: boolean
  permissions: string[]
  onWorkingChange?: (working: boolean) => void
}

const fullName = (item: { nombres: string; apellido_paterno: string; apellido_materno?: string | null }) =>
  [item.nombres, item.apellido_paterno, item.apellido_materno].filter(Boolean).join(' ')

export default function ColegioCoordinadores({
  colegioId,
  colegioNombre,
  colegioActivo,
  permissions,
  onWorkingChange,
}: Props) {
  const { confirm, confirmationDialog } = useConfirmation()
  const [coordinators, setCoordinators] = useState<CoordinadorColegioItem[]>([])
  const [coordinatorCandidates, setCoordinatorCandidates] = useState<UsuarioCoordinacionItem[]>([])
  const [monitorCandidatesByCoordinator, setMonitorCandidatesByCoordinator] = useState<Record<string, UsuarioCoordinacionItem[]>>({})
  const [selectedCoordinatorId, setSelectedCoordinatorId] = useState('')
  const [selectedMonitorId, setSelectedMonitorId] = useState('')
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [monitorsByCoordinator, setMonitorsByCoordinator] = useState<Record<string, MonitorCoordinadorItem[]>>({})
  const [loading, setLoading] = useState(true)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [multiSchoolWarning, setMultiSchoolWarning] = useState<{
    coordinadorId: string
    detail: MultiSchoolConflictDetail
  } | null>(null)

  const canManageCoordinators = permissions.includes('MANAGE_SCHOOL_COORDINATORS')
  const canManageMonitors = permissions.includes('MANAGE_COORDINATOR_MONITORS')

  const assignedCoordinatorIds = useMemo(
    () => new Set(coordinators.filter((item) => item.activo).map((item) => item.coordinador_id)),
    [coordinators],
  )
  const availableCoordinators = coordinatorCandidates.filter((user) => !assignedCoordinatorIds.has(user.id))

  useEffect(() => { onWorkingChange?.(working) }, [working, onWorkingChange])

  const loadBase = async () => {
    setLoading(true)
    setError(null)
    try {
      const [relations, candidates] = await Promise.all([
        getSchoolCoordinators(colegioId),
        canManageCoordinators ? getCoordinatorCandidates(colegioId) : Promise.resolve([]),
      ])
      setCoordinators(relations)
      setCoordinatorCandidates(candidates)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible cargar la coordinación del colegio.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void loadBase() }, [colegioId])

  const loadMonitors = async (coordinatorId: string) => {
    try {
      const [items, candidates] = await Promise.all([
        getCoordinatorMonitors(colegioId, coordinatorId),
        canManageMonitors ? getMonitorCandidates(colegioId, coordinatorId) : Promise.resolve([]),
      ])
      setMonitorsByCoordinator((previous) => ({ ...previous, [coordinatorId]: items }))
      setMonitorCandidatesByCoordinator((previous) => ({ ...previous, [coordinatorId]: candidates }))
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible cargar los monitores.')
    }
  }

  const toggleExpanded = (coordinatorId: string) => {
    const next = expandedId === coordinatorId ? null : coordinatorId
    setExpandedId(next)
    setSelectedMonitorId('')
    if (next && !monitorsByCoordinator[next]) void loadMonitors(next)
  }

  const assignCoordinator = async (confirmExceptional = false) => {
    if (!selectedCoordinatorId || working) return
    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      const created = await assignSchoolCoordinator(colegioId, selectedCoordinatorId, confirmExceptional)
      setCoordinators((previous) => [...previous.filter((item) => item.coordinador_id !== created.coordinador_id), created]
        .sort((a, b) => fullName(a).localeCompare(fullName(b), 'es')))
      setSelectedCoordinatorId('')
      setMultiSchoolWarning(null)
      setSuccess(`${fullName(created)} fue asignado a ${colegioNombre}.`)
    } catch (cause) {
      if (cause instanceof MultiSchoolAssignmentError) {
        setMultiSchoolWarning({ coordinadorId: selectedCoordinatorId, detail: cause.detail })
      } else {
        setError(cause instanceof Error ? cause.message : 'No fue posible asignar el coordinador.')
      }
    } finally {
      setWorking(false)
    }
  }

  const unassignCoordinator = async (item: CoordinadorColegioItem) => {
    if (!await confirm({
      title: '¿Desasignar coordinador?',
      message: <>
        <strong>{fullName(item)}</strong> dejará de coordinar <strong>{colegioNombre}</strong>.
        Sus relaciones con monitores de este colegio también quedarán inactivas, conservando historial.
      </>,
      confirmLabel: 'Sí, desasignar',
    })) return

    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      await unassignSchoolCoordinator(colegioId, item.coordinador_id)
      setCoordinators((previous) => previous.filter((current) => current.coordinador_id !== item.coordinador_id))
      setMonitorsByCoordinator((previous) => {
        const next = { ...previous }
        delete next[item.coordinador_id]
        return next
      })
      if (expandedId === item.coordinador_id) setExpandedId(null)
      setSuccess('Coordinador desasignado correctamente.')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible desasignar el coordinador.')
    } finally {
      setWorking(false)
    }
  }

  const assignMonitor = async (coordinatorId: string) => {
    if (!selectedMonitorId || working) return
    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      const created = await assignCoordinatorMonitor(colegioId, coordinatorId, selectedMonitorId)
      setMonitorsByCoordinator((previous) => ({
        ...previous,
        [coordinatorId]: [...(previous[coordinatorId] ?? []).filter((item) => item.monitor_id !== created.monitor_id), created]
          .sort((a, b) => fullName(a).localeCompare(fullName(b), 'es')),
      }))
      setSelectedMonitorId('')
      setSuccess(`${fullName(created)} fue asignado al coordinador.`)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible asignar el monitor.')
    } finally {
      setWorking(false)
    }
  }

  const unassignMonitor = async (coordinatorId: string, monitor: MonitorCoordinadorItem) => {
    if (!await confirm({
      title: '¿Desasignar monitor?',
      message: <><strong>{fullName(monitor)}</strong> dejará de pertenecer a este coordinador dentro de <strong>{colegioNombre}</strong>.</>,
      confirmLabel: 'Sí, desasignar',
    })) return

    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      await unassignCoordinatorMonitor(colegioId, coordinatorId, monitor.monitor_id)
      setMonitorsByCoordinator((previous) => ({
        ...previous,
        [coordinatorId]: (previous[coordinatorId] ?? []).filter((item) => item.monitor_id !== monitor.monitor_id),
      }))
      setSuccess('Monitor desasignado correctamente.')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible desasignar el monitor.')
    } finally {
      setWorking(false)
    }
  }

  if (loading) return <LoadingIndicator />

  return <section className="schools-form-section schools-coordination">
    {confirmationDialog}
    <div className="schools-coordination-heading">
      <div>
        <h3>Coordinadores del colegio</h3>
        <p>Asigna responsables y define qué monitores dependen de cada coordinador dentro de este establecimiento.</p>
      </div>
      <span className="schools-coordination-count">{coordinators.length} asignado{coordinators.length === 1 ? '' : 's'}</span>
    </div>

    {error && <p className="schools-error" role="alert">{error}</p>}
    {success && <p className="schools-success" role="status">{success}</p>}

    {canManageCoordinators && colegioActivo && <div className="schools-coordination-assign">
      <label>
        <span>Asignar coordinador</span>
        <select value={selectedCoordinatorId} disabled={working} onChange={(event) => {
          setSelectedCoordinatorId(event.target.value)
          setMultiSchoolWarning(null)
          setError(null)
          setSuccess(null)
        }}>
          <option value="">Selecciona un coordinador</option>
          {availableCoordinators.map((user) => <option key={user.id} value={user.id}>{fullName(user)} · {user.email}</option>)}
        </select>
      </label>
      <button className="schools-primary" type="button" disabled={!selectedCoordinatorId || working} onClick={() => { void assignCoordinator(false) }}>
        + Asignar coordinador
      </button>
    </div>}

    {multiSchoolWarning && <div className="schools-coordination-warning" role="alert">
      <strong>Este coordinador ya está asignado a otro colegio.</strong>
      <p>La asignación a más de un establecimiento debería utilizarse solo de forma excepcional.</p>
      <ul>{multiSchoolWarning.detail.colegios.map((school) => <li key={school.id}>{school.nombre}</li>)}</ul>
      <p>¿Quieres asignarlo también a <strong>{colegioNombre}</strong>?</p>
      <div className="schools-coordination-warning-actions">
        <button className="schools-secondary" type="button" disabled={working} onClick={() => setMultiSchoolWarning(null)}>Cancelar</button>
        <button className="schools-primary" type="button" disabled={working} onClick={() => { void assignCoordinator(true) }}>Asignar de todas formas</button>
      </div>
    </div>}

    {!coordinators.length ? <div className="schools-feedback">Todavía no hay coordinadores asignados a este colegio.</div> :
      <div className="schools-coordination-list">
        {coordinators.map((coordinator) => {
          const assignedMonitors = monitorsByCoordinator[coordinator.coordinador_id] ?? []
          const assignedMonitorIds = new Set(assignedMonitors.map((item) => item.monitor_id))
          const availableMonitors = (monitorCandidatesByCoordinator[coordinator.coordinador_id] ?? [])
            .filter((user) => !assignedMonitorIds.has(user.id))
          const expanded = expandedId === coordinator.coordinador_id
          return <article className="schools-coordinator-card" key={coordinator.coordinador_id}>
            <div className="schools-coordinator-summary">
              <div>
                <strong>{fullName(coordinator)}</strong>
                <span>{coordinator.email}</span>
                {coordinator.otros_colegios.length > 0 && <small>También asignado en {coordinator.otros_colegios.length} colegio{coordinator.otros_colegios.length === 1 ? '' : 's'}: {coordinator.otros_colegios.map((school) => school.nombre).join(', ')}</small>}
              </div>
              <div className="schools-coordinator-actions">
                <button className="schools-secondary" type="button" disabled={working} onClick={() => toggleExpanded(coordinator.coordinador_id)}>
                  {expanded ? 'Ocultar monitores' : 'Gestionar monitores'}
                </button>
                {canManageCoordinators && <button className="schools-danger-link" type="button" disabled={working} onClick={() => { void unassignCoordinator(coordinator) }}>Desasignar</button>}
              </div>
            </div>

            {expanded && <div className="schools-coordinator-monitors">
              <div className="schools-coordinator-monitors-heading">
                <div><h4>Monitores asignados</h4><p>Esta relación aplica únicamente dentro de {colegioNombre}.</p></div>
                <span>{assignedMonitors.length} monitor{assignedMonitors.length === 1 ? '' : 'es'}</span>
              </div>

              {canManageMonitors && colegioActivo && <div className="schools-monitor-assign">
                <select aria-label="Monitor a asignar" value={selectedMonitorId} disabled={working} onChange={(event) => setSelectedMonitorId(event.target.value)}>
                  <option value="">Selecciona un monitor</option>
                  {availableMonitors.map((user) => <option key={user.id} value={user.id}>{fullName(user)} · {user.email}</option>)}
                </select>
                <button className="schools-primary" type="button" disabled={!selectedMonitorId || working} onClick={() => { void assignMonitor(coordinator.coordinador_id) }}>+ Asignar monitor</button>
              </div>}

              {!assignedMonitors.length ? <p className="schools-coordinator-empty">Este coordinador todavía no tiene monitores asignados en este colegio.</p> :
                <div className="schools-monitor-list">{assignedMonitors.map((monitor) => <div className="schools-monitor-row" key={monitor.monitor_id}>
                  <div><strong>{fullName(monitor)}</strong><span>{monitor.email}</span></div>
                  {canManageMonitors && <button className="schools-danger-link" type="button" disabled={working} onClick={() => { void unassignMonitor(coordinator.coordinador_id, monitor) }}>Desasignar</button>}
                </div>)}</div>}
            </div>}
          </article>
        })}
      </div>}
  </section>
}
