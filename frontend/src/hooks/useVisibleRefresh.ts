/**
 * HuellApp · Actualización de pantallas visibles.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Programar consultas sin superposición y omitirlas cuando la pestaña está oculta.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - El consumidor pausa mediante enabled y comprueba isActive antes de aplicar resultados.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useEffect, useEffectEvent } from 'react'

/** El callback debe consultar isActive antes de aplicar una respuesta al estado. */
export function useVisibleRefresh(refresh: (isActive: () => boolean) => Promise<void>, enabled: boolean, delay = 15000) {
  // Usa el callback vigente sin reiniciar el intervalo en cada renderizado.
  const run = useEffectEvent(refresh)
  useEffect(() => {
    if (!enabled) return
    let stopped = false
    let pending = false
    const tick = async () => {
      if (stopped || pending || document.hidden) return
      pending = true
      try { await run(() => !stopped) } finally { pending = false }
    }
    const timer = window.setInterval(() => void tick(), delay)
    const focus = () => void tick()
    window.addEventListener('focus', focus)
    document.addEventListener('visibilitychange', focus)
    return () => {
      // Invalida respuestas pendientes; no cancela la solicitud HTTP en curso.
      stopped = true
      window.clearInterval(timer)
      window.removeEventListener('focus', focus)
      document.removeEventListener('visibilitychange', focus)
    }
  }, [enabled, delay])
}
