/**
 * HuellApp · Sustituto asíncrono de las confirmaciones del navegador.
 * Cada consumidor presenta el mismo diálogo; cancelar o desmontar resuelve false.
 * Evita abrir dos confirmaciones simultáneas desde el mismo componente.
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
