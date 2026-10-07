/**
 * HuellApp · Carga de selectores dependientes de colegio o ramo.
 * Descarta respuestas tardías y nunca presenta recursos de una selección anterior.
 * El estado de carga se deriva de la clave, sin cambios síncronos en efectos.
 */
import { useEffect, useState } from 'react'

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
  const current = key && result?.key === key && result.revision === revision ? result : null
  return { data: current?.data, error: current?.error, loading: !!key && !current, retry: () => setRevision((value) => value + 1) }
}
