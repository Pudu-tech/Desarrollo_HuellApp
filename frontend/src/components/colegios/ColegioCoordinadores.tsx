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

import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  MultiSchoolAssignmentError,
  assignCoordinatorMonitor,
  assignSchoolCoordinator,
  getCoordinatorCandidates,
  getCoordinatorMonitorPanel,
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
  section?: 'coordinadores' | 'monitores'
  colegioId: string
  colegioNombre: string
  colegioActivo: boolean
  permissions: string[]
  onWorkingChange?: (working: boolean) => void
}

const fullName = (item: { nombres: string; apellido_paterno: string; apellido_materno?: string | null }) =>
  [item.nombres, item.apellido_paterno, item.apellido_materno].filter(Boolean).join(' ')

const FLEXIBLE_MONITORS_KEY = 'huellapp:asignaciones-flexibles'

function readFlexibleMonitors(): string[] {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(FLEXIBLE_MONITORS_KEY) ?? '[]')
    return Array.isArray(saved) ? saved.filter((id): id is string => typeof id === 'string') : []
  } catch {
    return []
  }
}

export default function ColegioCoordinadores({
  section = 'coordinadores',
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
  const [monitorSelection, setMonitorSelection] = useState({ regular: '', flexible: '' })
  const [flexibleRelations, setFlexibleRelations] = useState(readFlexibleMonitors)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [monitorsByCoordinator, setMonitorsByCoordinator] = useState<Record<string, MonitorCoordinadorItem[]>>({})
  const [monitorErrors, setMonitorErrors] = useState<Record<string, string | null>>({})
  const [loading, setLoading] = useState(true)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [multiSchoolWarning, setMultiSchoolWarning] = useState<{
    coordinadorId: string
    detail: MultiSchoolConflictDetail
  } | null>(null)

  const showMonitors = section === 'monitores'
  const canManageCoordinators = !showMonitors && permissions.includes('MANAGE_SCHOOL_COORDINATORS')
  const canManageMonitors = showMonitors && permissions.includes('MANAGE_COORDINATOR_MONITORS')

  const assignedCoordinatorIds = useMemo(
    () => new Set(coordinators.filter((item) => item.activo).map((item) => item.coordinador_id)),
    [coordinators],
  )
  const availableCoordinators = coordinatorCandidates.filter((user) => !assignedCoordinatorIds.has(user.id))

  useEffect(() => { onWorkingChange?.(working) }, [working, onWorkingChange])

  const loadMonitors = useCallback(async (coordinatorId: string, fresh = false) => {
    setMonitorErrors((previous) => ({ ...previous, [coordinatorId]: null }))
    try {
      const { asignados, candidatos } = await getCoordinatorMonitorPanel(colegioId, coordinatorId, fresh)
      setMonitorsByCoordinator((previous) => ({ ...previous, [coordinatorId]: asignados }))
      setMonitorCandidatesByCoordinator((previous) => ({ ...previous, [coordinatorId]: candidatos }))
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : 'No fue posible cargar los monitores.'
      setMonitorErrors((previous) => ({ ...previous, [coordinatorId]: message }))
    }
  }, [colegioId])

  useEffect(() => {
    let active = true
    void Promise.all([
      getSchoolCoordinators(colegioId),
      canManageCoordinators ? getCoordinatorCandidates(colegioId) : Promise.resolve([]),
    ]).then(([relations, candidates]) => {
      if (!active) return
      setCoordinators(relations)
      setCoordinatorCandidates(candidates)
      if (showMonitors && relations.length === 1) {
        const coordinatorId = relations[0].coordinador_id
        setExpandedId(coordinatorId)
        void loadMonitors(coordinatorId)
      }
    }).catch((cause: unknown) => {
      if (active) setError(cause instanceof Error ? cause.message : 'No fue posible cargar la coordinación del colegio.')
    }).finally(() => {
      if (active) setLoading(false)
    })
    return () => { active = false }
  }, [colegioId, canManageCoordinators, showMonitors, loadMonitors])

  const selectMonitorCoordinator = (coordinatorId: string) => {
    setExpandedId(coordinatorId || null)
    setMonitorSelection({ regular: '', flexible: '' })
    setError(null)
    setSuccess(null)
    if (coordinatorId && !monitorsByCoordinator[coordinatorId]) void loadMonitors(coordinatorId)
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

  function markFlexible(relationId: string, flexible: boolean) {
    const updated = new Set(readFlexibleMonitors())
    if (flexible) updated.add(relationId)
    else updated.delete(relationId)
    const relations = [...updated]
    setFlexibleRelations(relations)
    try {
      localStorage.setItem(FLEXIBLE_MONITORS_KEY, JSON.stringify(relations))
    } catch { /* La etiqueta sigue visible durante esta sesión. */ }
  }

  const assignMonitor = async (coordinatorId: string, monitorId: string, flexible: boolean) => {
    if (!monitorId || working) return
    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      const created = await assignCoordinatorMonitor(colegioId, coordinatorId, monitorId)
      setMonitorsByCoordinator((previous) => ({
        ...previous,
        [coordinatorId]: [...(previous[coordinatorId] ?? []).filter((item) => item.monitor_id !== monitorId), created]
          .sort((a, b) => fullName(a).localeCompare(fullName(b), 'es')),
      }))
      markFlexible(created.relation_id, flexible)
      setMonitorSelection({ regular: '', flexible: '' })
      setSuccess(`${fullName(created)} fue asignado al coordinador.`)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible asignar el monitor.')
    } finally {
      setWorking(false)
    }
  }

  const unassignMonitor = async (coordinatorId: string, monitor: MonitorCoordinadorItem) => {
    if (!await confirm({
      title: '¿Quitar monitor?',
      message: <><strong>{fullName(monitor)}</strong> dejará de pertenecer a este coordinador dentro de <strong>{colegioNombre}</strong>.</>,
      confirmLabel: 'Sí, quitar monitor',
    })) return

    setWorking(true)
    setError(null)
    setSuccess(null)
    try {
      await unassignCoordinatorMonitor(colegioId, coordinatorId, monitor.monitor_id)
      markFlexible(monitor.relation_id, false)
      setMonitorsByCoordinator((previous) => ({
        ...previous,
        [coordinatorId]: (previous[coordinatorId] ?? []).filter((item) => item.monitor_id !== monitor.monitor_id),
      }))
      setSuccess('Monitor retirado de la lista del coordinador.')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible quitar el monitor.')
    } finally {
      setWorking(false)
    }
  }

  if (loading) return <LoadingIndicator />

  return <section className="schools-form-section schools-coordination">
    {confirmationDialog}
    <div className="schools-coordination-heading">
      <div>
        <h3>{showMonitors ? 'Monitores del colegio' : 'Coordinadores del colegio'}</h3>
        {showMonitors && <p>Consulta y asigna monitores por coordinador en este colegio.</p>}
      </div>
      {!showMonitors && <span className="schools-coordination-count">{coordinators.length} asignado{coordinators.length === 1 ? '' : 's'}</span>}
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

    {showMonitors && coordinators.length > 1 && <div className="schools-coordination-assign">
      <label>
        <span>Coordinador para gestionar monitores</span>
        <select value={expandedId ?? ''} disabled={working} onChange={(event) => selectMonitorCoordinator(event.target.value)}>
          <option value="">Selecciona un coordinador</option>
          {coordinators.map((item) => <option key={item.coordinador_id} value={item.coordinador_id}>{fullName(item)}</option>)}
        </select>
      </label>
    </div>}

    {!coordinators.length ? <div className="schools-feedback">{showMonitors
      ? 'Asigna un coordinador en la pestaña Coordinadores para poder asignar monitores.'
      : 'Todavía no hay coordinadores asignados a este colegio.'}</div> :
      <div className="schools-coordination-list">
        {coordinators.filter((item) => !showMonitors || item.coordinador_id === expandedId).map((coordinator) => {
          const assignedMonitors = monitorsByCoordinator[coordinator.coordinador_id] ?? []
          const assignedMonitorIds = new Set(assignedMonitors.map((item) => item.monitor_id))
          const availableMonitors = (monitorCandidatesByCoordinator[coordinator.coordinador_id] ?? [])
            .filter((user) => !assignedMonitorIds.has(user.id))
          const expanded = expandedId === coordinator.coordinador_id
          const monitorError = monitorErrors[coordinator.coordinador_id]
          return <article className="schools-coordinator-card" key={coordinator.coordinador_id}>
            {!showMonitors && <div className="schools-coordinator-summary">
              <div>
                <strong>{fullName(coordinator)}</strong>
                <span>{coordinator.email}</span>
                {coordinator.otros_colegios.length > 0 && <small>También asignado en {coordinator.otros_colegios.length} colegio{coordinator.otros_colegios.length === 1 ? '' : 's'}: {coordinator.otros_colegios.map((school) => school.nombre).join(', ')}</small>}
              </div>
              <div className="schools-coordinator-actions">
                {canManageCoordinators && <button className="schools-danger-link" type="button" disabled={working} onClick={() => { void unassignCoordinator(coordinator) }}>Desasignar</button>}
              </div>
            </div>}

            {expanded && monitorError && <div className="schools-coordinator-monitors">
              <p className="schools-error" role="alert">{monitorError}</p>
              <button className="schools-secondary" type="button" onClick={() => { void loadMonitors(coordinator.coordinador_id, true) }}>Reintentar carga</button>
            </div>}
            {expanded && !monitorsByCoordinator[coordinator.coordinador_id] && !monitorError && <LoadingIndicator />}
            {expanded && monitorsByCoordinator[coordinator.coordinador_id] && !monitorError && <div className="schools-coordinator-monitors">
              <div className="schools-coordinator-monitors-heading">
                <h4>Monitores asignados</h4>
                <span>{assignedMonitors.length} monitor{assignedMonitors.length === 1 ? '' : 'es'}</span>
              </div>

              {(['regular', 'flexible'] as const).map((group) => {
                const flexible = group === 'flexible'
                const monitors = assignedMonitors.filter((monitor) => flexibleRelations.includes(monitor.relation_id) === flexible)
                const selected = monitorSelection[group]
                return <section className="schools-monitors-group" key={group}>
                  <h5>{flexible ? 'Monitores flexibles asignados' : 'Monitores asignados al colegio'}</h5>
                  {monitors.length === 0 ? <p className="schools-coordinator-empty">
                    {flexible ? 'Todavía no hay monitores flexibles asignados.' : 'Todavía no hay monitores asignados en este grupo.'}
                  </p> : <div className="schools-monitor-list">{monitors.map((monitor) => <div className="schools-monitor-row" key={monitor.relation_id}>
                    <div><strong>{fullName(monitor)}</strong><span>{monitor.email}</span></div>
                    {canManageMonitors && <div className="schools-coordinator-actions">
                      <button className="schools-danger-link" type="button" disabled={working} onClick={() => { void unassignMonitor(coordinator.coordinador_id, monitor) }}>Quitar monitor</button>
                    </div>}
                  </div>)}</div>}
                  {canManageMonitors && colegioActivo && <div className="schools-monitor-assign">
                    <select aria-label={flexible ? 'Monitor flexible a asignar' : 'Monitor a asignar'} value={selected} disabled={working} onChange={(event) => setMonitorSelection({ ...monitorSelection, [group]: event.target.value })}>
                      <option value="">Selecciona un monitor</option>
                      {availableMonitors.map((user) => <option key={user.id} value={user.id}>{fullName(user)} · {user.email}</option>)}
                    </select>
                    <button className="schools-primary" type="button" disabled={!selected || working} onClick={() => { void assignMonitor(coordinator.coordinador_id, selected, flexible) }}>
                      {flexible ? '+ Asignar monitor flexible' : '+ Asignar monitor'}
                    </button>
                  </div>}
                </section>
              })}
            </div>}
          </article>
        })}
      </div>}
  </section>
}
