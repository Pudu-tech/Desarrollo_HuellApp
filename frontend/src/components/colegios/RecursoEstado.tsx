/**
 * HuellApp · Acciones de estado de recursos escolares.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Presentar activación, desactivación y eliminación según las capacidades recibidas.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Eliminación al final de la edición mediante confirmación explícita.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useConfirmation } from '../../hooks/useConfirmation'

interface Props {
  nombre: string
  activo: boolean
  working: boolean
  canToggle: boolean
  canDelete: boolean
  onToggle: () => void
  onDelete: () => void
}

/** Presenta el estado confirmado; no cambia datos antes de recibir aprobación. */
export default function RecursoEstado({ nombre, activo, working, canToggle, canDelete, onToggle, onDelete }: Props) {
  const { confirm, confirmationDialog } = useConfirmation()
  return <section className="schools-status-section schools-form-section">
    {confirmationDialog}
    <h4>Estado y administración</h4>
    <p>La desactivación es reversible. Los registros históricos se conservan.</p>
    {canToggle && <button type="button" className="schools-secondary" disabled={working} onClick={async () => {
      const action = activo ? 'desactivar' : 'reactivar'
      if (await confirm({ title: `¿${activo ? 'Desactivar' : 'Reactivar'} ${nombre}?`,
        message: <>Vas a {action} <strong>{nombre}</strong>. Este cambio es reversible y conserva el historial.</>,
        confirmLabel: `Sí, ${action}` })) onToggle()
    }}>{activo ? 'Desactivar' : 'Reactivar'}</button>}
    {canDelete && <div className="schools-contacts-delete">
      <p>La eliminación lógica no se puede deshacer desde esta interfaz. Si hay instancias futuras vigentes, debes cancelarlas o reasignarlas primero.</p>
      <button type="button" className="schools-danger" disabled={working} onClick={async () => {
        if (await confirm({ title: '¿Eliminar registro?',
          message: <>Vas a eliminar <strong>{nombre}</strong>. Dejará de estar disponible. Esta acción no se puede deshacer desde la interfaz. El historial se conservará y quedará registro en auditoría.</>,
          confirmLabel: 'Sí, eliminar' })) onDelete()
      }}>Eliminar</button>
    </div>}
  </section>
}
