import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import ts from 'typescript'

const source = fs.readFileSync(new URL('../src/config/navigation.ts', import.meta.url), 'utf8')
const javascript = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText
const { ADMIN_NAVIGATION_ITEMS, MONITOR_NAVIGATION_ITEMS } = await import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`)
const paths = (role) => (role === 'MONITOR' ? MONITOR_NAVIGATION_ITEMS : ADMIN_NAVIGATION_ITEMS)
  .filter((item) => item.allowedRoles.includes(role)).map((item) => item.path)

test('Directiva accede a todos los módulos de administración', () => {
  assert.deepEqual(paths('DIRECTIVA').filter((path) => path !== '/app/mis-asignaciones'), paths('SUPERADMIN'))
})
test('Coordinador accede a inicio, gestión y respuestas propias de asignaciones', () => {
  assert.deepEqual(paths('COORDINADOR'), ['/app/inicio', '/app/asignaciones', '/app/mis-asignaciones'])
})
test('Monitor solo accede a inicio y asignaciones propias', () => {
  assert.deepEqual(paths('MONITOR'), ['/app/monitor', '/app/monitor/asignaciones'])
})
