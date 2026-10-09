/**
 * HuellApp · Confirmación accesible de eliminación lógica del colegio.
 * El diálogo nativo conserva el foco y bloquea la interacción con la ficha.
 * Escape/cancelación quedan deshabilitados mientras se confirma la transacción.
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
      Se conservarán las asignaciones históricas y quedará registro en auditoría.
  </ConfirmationDialog>
}
