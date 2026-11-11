/**
 * HuellApp · Estado de los recursos del colegio.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Centralizar carga, mensajes y escrituras de los mantenedores escolares.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Bloquea escrituras simultáneas y aplica la respuesta confirmada por la API.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useEffect, useRef, useState } from 'react'
import { clearReadCache } from '../services/readCache'

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

  /** Ejecuta una escritura y aplica su respuesta confirmada; informa al padre si está ocupada. */
  async function run<R>(operation: () => Promise<R>, success: string, apply: (result: R) => void): Promise<boolean> {
    // La referencia bloquea dobles clics incluso antes del siguiente renderizado.
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

  /** Invalida la caché de lectura y fuerza una nueva carga del listado. */
  function refresh() { clearReadCache(); setLoading(true); setRevision((value) => value + 1) }
  /** Limpia los mensajes de operaciones sin modificar los recursos cargados. */
  function clearFeedback() { setError(''); setMessage('') }
  return { items, setItems, loading, loadError, error, setError, message, working, run, refresh, clearFeedback }
}
