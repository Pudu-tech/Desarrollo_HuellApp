/**
 * HuellApp · Confirmaciones asíncronas.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Exponer una promesa de confirmación y el diálogo que debe renderizar el consumidor.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Cancelar o desmontar resuelve false; evita confirmaciones simultáneas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import ConfirmationDialog from '../components/common/ConfirmationDialog'

interface Confirmation {
  title: string
  message: ReactNode
  confirmLabel: string
}

export function useConfirmation() {
  const [request, setRequest] = useState<Confirmation | null>(null)
  const resolver = useRef<((approved: boolean) => void) | null>(null)
  useEffect(() => () => { resolver.current?.(false); resolver.current = null }, [])

  const confirm = useCallback((options: Confirmation): Promise<boolean> => {
    if (resolver.current) return Promise.resolve(false)
    return new Promise((resolve) => { resolver.current = resolve; setRequest(options) })
  }, [])

  /** Resuelve la confirmación pendiente y limpia el diálogo para permitir otra solicitud. */
  function settle(approved: boolean) {
    const resolve = resolver.current
    resolver.current = null
    setRequest(null)
    resolve?.(approved)
  }

  const confirmationDialog = request && <ConfirmationDialog title={request.title} confirmLabel={request.confirmLabel}
    onCancel={() => settle(false)} onConfirm={() => settle(true)}>{request.message}</ConfirmationDialog>
  return { confirm, confirmationDialog }
}
