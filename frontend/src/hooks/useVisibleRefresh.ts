import { useEffect, useEffectEvent } from 'react'

/** Actualiza sin peticiones superpuestas y pausa mientras se edita o la pestaña está oculta. */
export function useVisibleRefresh(refresh: (isActive: () => boolean) => Promise<void>, enabled: boolean, delay = 15000) {
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
      stopped = true
      window.clearInterval(timer)
      window.removeEventListener('focus', focus)
      document.removeEventListener('visibilitychange', focus)
    }
  }, [enabled, delay])
}
