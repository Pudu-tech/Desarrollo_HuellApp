import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import ts from 'typescript'

const source = fs.readFileSync(new URL('../src/utils/asignacionesListado.ts', import.meta.url), 'utf8')
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } })
const { ordenarPorFecha, colegiosDisponibles } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`)

test('Ordena fechas y horarios en ambos sentidos sin modificar el listado original', () => {
  const items = [
    { id: 'late', fecha: '2026-10-20', hora_inicio: '11:00' },
    { id: 'old', fecha: '2025-12-31', hora_inicio: '18:00' },
    { id: 'early', fecha: '2026-10-20', hora_inicio: '08:00' },
  ]
  assert.deepEqual(ordenarPorFecha(items, 'asc').map(x => x.id), ['old', 'early', 'late'])
  assert.deepEqual(ordenarPorFecha(items, 'desc').map(x => x.id), ['late', 'early', 'old'])
  assert.deepEqual(items.map(x => x.id), ['late', 'old', 'early'])
  assert.deepEqual(ordenarPorFecha([], 'asc'), [])
})

test('El selector excluye colegios inactivos y eliminados, conservando el catálogo histórico', () => {
  const schools = [
    { id: 'current', activo: true, deleted_at: null },
    { id: 'inactive', activo: false, deleted_at: null },
    { id: 'deleted', activo: true, deleted_at: '2026-10-20' },
  ]
  assert.deepEqual(colegiosDisponibles(schools).map(x => x.id), ['current'])
  assert.equal(schools.length, 3)
})
