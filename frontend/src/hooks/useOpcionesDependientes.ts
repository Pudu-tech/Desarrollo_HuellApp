/**
 * HuellApp · Opciones de selectores dependientes.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Consultar opciones por clave y descartar resultados de selecciones anteriores.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Clave vacía desactiva la carga; revision permite reintentar.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useEffect, useState } from 'react'

/** Consulta por clave; una clave vacía desactiva la carga y retry fuerza otro intento. */
export function useOpcionesDependientes<T>(key: string, fetcher: (key: string) => Promise<T>) {
  const [revision, setRevision] = useState(0)
  const [result, setResult] = useState<{ key: string; revision: number; data?: T; error?: string } | null>(null)
  useEffect(() => {
    if (!key) return
    let active = true
    void fetcher(key)
      .then((data) => { if (active) setResult({ key, revision, data }) })
      .catch((cause: unknown) => { if (active) setResult({ key, revision, error: cause instanceof Error ? cause.message : 'No fue posible cargar las opciones.' }) })
    return () => { active = false }
  }, [key, revision, fetcher])
  // Oculta el resultado anterior desde el cambio de selección, antes de que termine la nueva petición.
  const current = key && result?.key === key && result.revision === revision ? result : null
  return { data: current?.data, error: current?.error, loading: !!key && !current, retry: () => setRevision((value) => value + 1) }
}
