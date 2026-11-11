/**
 * HuellApp · Diálogo común de confirmación.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Pedir confirmación explícita y bloquear cierres durante operaciones pendientes.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Utiliza el diálogo nativo para gestionar el foco y la interacción modal.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useEffect, useId, useRef, type ReactNode } from 'react'
import '../../styles/confirmation-dialog.css'

interface Props {
  title: string
  children: ReactNode
  confirmLabel: string
  working?: boolean
  workingLabel?: string
  error?: string | null
  onCancel: () => void
  onConfirm: () => void
}

export default function ConfirmationDialog({ title, children, confirmLabel, working = false,
  workingLabel = 'Procesando…', error, onCancel, onConfirm }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const id = useId()
  useEffect(() => {
    const dialog = ref.current
    dialog?.showModal()
    return () => { dialog?.close() }
  }, [])

  return <dialog ref={ref} className="confirmation-dialog" aria-labelledby={`${id}-title`} aria-describedby={`${id}-description`}
    onCancel={(event) => { event.preventDefault(); if (!working) onCancel() }}>
    <h2 id={`${id}-title`}>{title}</h2>
    <p id={`${id}-description`}>{children}</p>
    {error && <p className="confirmation-dialog-error" role="alert">{error}</p>}
    <div className="confirmation-dialog-actions">
      <button type="button" className="confirmation-dialog-cancel" disabled={working} onClick={onCancel}>Cancelar</button>
      <button type="button" className="confirmation-dialog-confirm" disabled={working} onClick={onConfirm}>{working ? workingLabel : confirmLabel}</button>
    </div>
  </dialog>
}
