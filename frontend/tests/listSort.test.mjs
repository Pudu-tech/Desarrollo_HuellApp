/**
 * HuellApp · Pruebas de comparación estable y ordenación de listados.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Comprobar comparación estable y ordenación de listados con el runner de Node.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Casos de regresión sobre los módulos TypeScript del frontend.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Las pruebas no conceden permisos ni sustituyen las comprobaciones de la API.
 */
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import ts from 'typescript'

const source = fs.readFileSync(new URL('../src/utils/listSort.ts', import.meta.url), 'utf8')
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } })
const { sortList, dateSortValue } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`)

test('Orden español respeta tildes, mayúsculas y ñ en ambos sentidos', () => {
  const names = ['Óscar', 'Ana', 'Ñora', 'Nora', 'álvaro']
  const ascending = ['álvaro', 'Ana', 'Nora', 'Ñora', 'Óscar']
  assert.deepEqual(sortList(names, x => x, 'asc'), ascending)
  assert.deepEqual(sortList(names, x => x, 'desc'), [...ascending].reverse())
  assert.deepEqual(names, ['Óscar', 'Ana', 'Ñora', 'Nora', 'álvaro'])
})

test('Orden natural de cursos y salas evita poner el 10 antes del 2', () => {
  assert.deepEqual(sortList(['Sala 10', 'Sala 2', 'Sala 1'], x => x, 'asc'), ['Sala 1', 'Sala 2', 'Sala 10'])
})

test('Fechas se comparan por su instante, con zonas horarias diferentes', () => {
  const values = ['2026-10-20T01:00:00-03:00', '2026-10-20T03:00:00Z', '2026-10-19T20:00:00-03:00']
  assert.deepEqual(sortList(values, dateSortValue, 'asc'), [values[2], values[1], values[0]])
})

test('Fechas vacías o inválidas quedan al final en ambos sentidos', () => {
  const values = [null, '2026-10-20', undefined, '2026-10-19', 'invalid']
  for (const direction of ['asc', 'desc']) {
    const ordered = sortList(values, dateSortValue, direction)
    assert.deepEqual(ordered.slice(2), [null, undefined, 'invalid'])
    assert.deepEqual(ordered.slice(0, 2), direction === 'asc' ? ['2026-10-19', '2026-10-20'] : ['2026-10-20', '2026-10-19'])
  }
})

test('Empates conservan orden y objetos originales; maneja listas vacías', () => {
  const items = [{ name: 'Ana', id: 1 }, { name: 'ana', id: 2 }]
  assert.deepEqual(sortList(items, x => x.name, 'desc').map(x => x.id), [1, 2])
  assert.equal(sortList(items, x => x.name, 'asc')[0], items[0])
  assert.deepEqual(sortList([], x => x, 'asc'), [])
})
