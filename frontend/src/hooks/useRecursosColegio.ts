/**
 * HuellApp · Estado compartido de los mantenedores de recursos del colegio.
 * Las operaciones actualizan la lista con la respuesta confirmada del backend.
 * Una carga fallida no se presenta como lista vacía; permite reintentar.
 */
import { useEffect, useRef, useState } from 'react'

/** Centraliza carga, errores, mensajes y exclusión de operaciones simultáneas. */
export function useRecursosColegio<T extends { id: string }>(
  colegioId: string,
  list: (id: string) => Promise<T[]>,
  onWorkingChange: (working: boolean) => void,
) {
  const [items, setItems] = useState<T[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [working, setWorking] = useState(false)
  const [revision, setRevision] = useState(0)
  const writing = useRef(false)

  useEffect(() => {
    let active = true
    void list(colegioId)
      .then((data) => { if (active) { setItems(data); setLoadError('') } })
      .catch((cause: unknown) => { if (active) setLoadError(cause instanceof Error ? cause.message : 'No se pudo cargar el listado.') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [colegioId, list, revision])

  /** La ficha permanece abierta mientras hay una escritura pendiente. */
  async function run<R>(operation: () => Promise<R>, success: string, apply: (result: R) => void): Promise<boolean> {
    if (writing.current) return false
    writing.current = true
    setWorking(true)
    onWorkingChange(true)
    setError('')
    setMessage('')
    try {
      const result = await operation()
      apply(result)
      setMessage(success)
      return true
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible completar la operación.')
      return false
    } finally {
      setWorking(false)
      writing.current = false
      onWorkingChange(false)
    }
  }

  function refresh() { setLoading(true); setRevision((value) => value + 1) }
  function clearFeedback() { setError(''); setMessage('') }
  return { items, setItems, loading, loadError, error, setError, message, working, run, refresh, clearFeedback }
}
