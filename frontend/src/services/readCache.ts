/** Lecturas por sesión, solo en memoria. Escrituras y actualización manual invalidan. */
const entries = new Map<string, { response: Response; until: number }>()
const pending = new Map<string, Promise<Response>>()
let scope = ''
let generation = 0

export function clearReadCache() {
  generation += 1
  entries.clear()
  pending.clear()
}

export async function cachedFetch(url: string, init: RequestInit = {}): Promise<Response> {
  const authorization = new Headers(init.headers).get('Authorization') ?? ''
  if (scope !== authorization) { clearReadCache(); scope = authorization }
  const method = (init.method ?? 'GET').toUpperCase()
  const cacheable = method === 'GET' && !!authorization && !/\/auth\/me|\/creacion|\/edicion|\/reasignacion|\/gestion-participantes|\/mi-participacion(?:\/|$)/.test(url)
  if (!cacheable) {
    if (method !== 'GET') clearReadCache()
    const response = await fetch(url, init)
    if ((method !== 'GET' && response.ok) || response.status === 401 || response.status === 403) clearReadCache()
    return response
  }
  const cached = entries.get(url)
  if (init.cache !== 'reload' && cached && cached.until > Date.now()) return cached.response.clone()
  const existing = pending.get(url)
  if (existing) return (await existing).clone()
  const revision = generation
  const request = fetch(url, init).then((response) => {
    if (response.ok && generation === revision) {
      if (entries.size >= 100) entries.delete(entries.keys().next().value!)
      const ttl = url.includes('/auth/permissions') ? 30_000
        : /\/catalogos\/(regiones|comunas|tipos-dependencia|niveles-curso)(?:\?|$)/.test(url) ? 600_000 : 120_000
      entries.set(url, { response: response.clone(), until: Date.now() + ttl })
    } else if (response.status === 401 || response.status === 403) clearReadCache()
    return response
  })
  pending.set(url, request)
  try { return (await request).clone() }
  finally { if (pending.get(url) === request) pending.delete(url) }
}
