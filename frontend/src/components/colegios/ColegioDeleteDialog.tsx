/**
 * HuellApp · Confirmación de eliminación del colegio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Solicitar confirmación de eliminación lógica y mostrar el estado de la operación.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Diálogo nativo con foco modal; no permite cancelar durante el envío.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import ConfirmationDialog from '../common/ConfirmationDialog'
import type { ColegioListItem } from '../../types/colegios'

interface Props {
  colegio: ColegioListItem
  working: boolean
  error: string | null
  onCancel: () => void
  onConfirm: () => void
}

export default function ColegioDeleteDialog({ colegio, working, error, onCancel, onConfirm }: Props) {
  return <ConfirmationDialog title="¿Eliminar colegio?" confirmLabel="Sí, eliminar colegio" working={working}
    workingLabel="Eliminando…" error={error} onCancel={onCancel} onConfirm={onConfirm}>
      Vas a eliminar <strong>{colegio.nombre}</strong>{colegio.rbd ? ` (RBD ${colegio.rbd})` : ''}.
      También se eliminarán lógicamente sus cursos, salas y contactos.
      Esta acción no se puede deshacer desde la interfaz.
      Se conservarán las instancias históricas y quedará registro en auditoría.
  </ConfirmationDialog>
}
