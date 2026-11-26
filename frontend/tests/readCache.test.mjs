/**
 * HuellApp · Pruebas de caducidad, aislamiento e invalidación de caché.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Comprobar caducidad, aislamiento e invalidación de caché con el runner de Node.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Casos de regresión sobre los módulos TypeScript del frontend.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Las pruebas no conceden permisos ni sustituyen las comprobaciones de la API.
 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
import ts from 'typescript'

async function harness() {
  const calls = []
  const context = vm.createContext({ Headers, Date, setTimeout, fetch: async (url, init) => {
    calls.push({ url, init })
    return new Response(JSON.stringify({ version: calls.length }), { status: 200 })
  } })
  const source = ts.transpileModule(fs.readFileSync(new URL('../src/services/readCache.ts', import.meta.url), 'utf8'),
    { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText
  const module = new vm.SourceTextModule(source, { context })
  await module.link(() => { throw new Error('Unexpected import') })
  await module.evaluate()
  return { ...module.namespace, calls, context }
}
const headers = { Authorization: 'Bearer user-a' }

test('Un 503 temporal se reintenta una vez y las lecturas simultáneas comparten el resultado', async () => {
  const { cachedFetch, context } = await harness()
  let reads = 0
  context.fetch = async () => new Response('{}', { status: ++reads === 1 ? 503 : 200 })
  const [permissions, duplicate] = await Promise.all([
    cachedFetch('/auth/permissions', { headers }),
    cachedFetch('/auth/permissions', { headers }),
  ])
  assert.equal(permissions.status, 200)
  assert.equal(duplicate.status, 200)
  assert.equal(reads, 2)
})

test('Cada exportación solicita un corte nuevo y no reutiliza respuestas en caché', async () => {
  const { cachedFetch, calls } = await harness()
  for (const url of ['/exports/users', '/exports/assignments', '/asistencias/exportacion?fecha_desde=2026-11-01', '/asistencias/mias/exportacion']) {
    await cachedFetch(url, { headers })
    await cachedFetch(url, { headers })
    const results = await Promise.all([cachedFetch(url, { headers }), cachedFetch(url, { headers })])
    assert.notDeepEqual(await results[0].json(), await results[1].json())
  }
  assert.equal(calls.length, 16)
})

test('La actualización de fondo renueva solo la lectura solicitada y conserva otros catálogos', async () => {
  const { cachedFetch, calls } = await harness()
  await cachedFetch('/catalogos', { headers })
  await cachedFetch('/asignaciones/resumen', { headers })
  const fresh = await cachedFetch('/asignaciones/resumen', { headers, cache: 'reload' })
  const reused = await cachedFetch('/asignaciones/resumen', { headers })
  assert.deepEqual(await fresh.json(), await reused.json())
  await cachedFetch('/catalogos', { headers })
  assert.equal(calls.length, 3)
})

test('Los paneles propios siempre consultan cambios y eliminaciones recientes', async () => {
  const { cachedFetch, calls } = await harness()
  for (const url of ['/asignaciones/mi-participacion', '/asignaciones/mi-participacion/id']) {
    await cachedFetch(url, { headers })
    await cachedFetch(url, { headers })
  }
  assert.equal(calls.length, 4)
})

test('Reabrir y lecturas simultáneas reutilizan una petición con cuerpos independientes', async () => {
  const { cachedFetch, calls } = await harness()
  const responses = await Promise.all([cachedFetch('/asignaciones', { headers }), cachedFetch('/asignaciones', { headers })])
  assert.deepEqual(await responses[0].json(), await responses[1].json())
  await (await cachedFetch('/asignaciones', { headers })).json()
  assert.equal(calls.length, 1)
})
test('Las escrituras y Actualizar invalidan las lecturas previas', async () => {
  const { cachedFetch, clearReadCache, calls } = await harness()
  await cachedFetch('/asignaciones', { headers })
  await cachedFetch('/asignaciones/id', { headers, method: 'PATCH' })
  await cachedFetch('/asignaciones', { headers })
  clearReadCache()
  await cachedFetch('/asignaciones', { headers })
  assert.equal(calls.length, 4)
})
test('Cambio de sesión, formularios y respuestas fallidas nunca reutilizan datos anteriores', async () => {
  const { cachedFetch, calls, context } = await harness()
  await cachedFetch('/asignaciones', { headers })
  await cachedFetch('/asignaciones', { headers: { Authorization: 'Bearer user-b' } })
  await cachedFetch('/catalogos/asignaciones/creacion', { headers })
  await cachedFetch('/catalogos/asignaciones/creacion', { headers })
  assert.equal(calls.length, 4)
  let errors = 0
  context.fetch = async () => { errors++; return new Response('{}', { status: 403 }) }
  await cachedFetch('/users', { headers })
  await cachedFetch('/users', { headers })
  assert.equal(errors, 2)
})
test('Una lectura anterior a una escritura no vuelve a poblar la caché', async () => {
  const { cachedFetch, context } = await harness()
  let finish
  context.fetch = () => new Promise((resolve) => { finish = resolve })
  const read = cachedFetch('/asignaciones', { headers })
  context.fetch = async () => new Response('{}')
  await cachedFetch('/asignaciones/id', { headers, method: 'DELETE' })
  finish(new Response('{}'))
  await read
  let reads = 0
  context.fetch = async () => { reads++; return new Response('{}') }
  await cachedFetch('/asignaciones', { headers })
  assert.equal(reads, 1)
})
