import { useEffect, useSyncExternalStore } from 'react'
import { recursoRequest } from '../services/recursosService'

const photos = new Map<string, { url: string | null; until: number }>()
const pending = new Map<string, Promise<void>>()
const listeners = new Set<() => void>()
let generation = 0
const notify = () => listeners.forEach(listener => listener())
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => { listeners.delete(listener) }
}

export function clearProfilePhotos() {
  generation += 1
  photos.clear()
  pending.clear()
  notify()
}

export function updateProfilePhoto(userId: string, url: string | null) {
  // Las URL firmadas duran una hora; renueva antes de su vencimiento.
  photos.set(userId, { url, until: Date.now() + 50 * 60_000 })
  notify()
}

export function useProfilePhoto(userId: string | undefined, path: string) {
  const url = useSyncExternalStore(subscribe, () => userId ? photos.get(userId)?.url ?? null : null)
  useEffect(() => {
    const load = async () => {
      if (!userId || (photos.get(userId)?.until ?? 0) > Date.now()) return
      const existing = pending.get(userId)
      if (existing) return existing
      const revision = generation
      const previous = photos.get(userId)
      const request = recursoRequest<{ foto_url: string | null }>(path, 'GET', undefined, true)
        .then(profile => {
          if (revision === generation && photos.get(userId) === previous) updateProfilePhoto(userId, profile.foto_url)
        })
        .catch(() => { /* Mantiene el saludo y las iniciales ante un fallo temporal. */ })
      pending.set(userId, request)
      try { await request } finally { if (pending.get(userId) === request) pending.delete(userId) }
    }
    void load()
    const timer = window.setInterval(() => { if (!document.hidden) void load() }, 60_000)
    return () => { window.clearInterval(timer) }
  }, [userId, path])
  return url
}
