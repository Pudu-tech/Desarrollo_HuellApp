import { describe, expect, test } from 'vitest'
import { dateSortValue, sortList } from '../../src/utils/listSort'
import type { SortValue } from '../../src/utils/listSort'

// Vitest transforma TypeScript directamente; se ejecuta el módulo real, sin transpilar copias ni mocks.
describe('sortList', () => {
  test('ordena nombres en español respetando tildes, mayúsculas y ñ', () => {
    const names = Object.freeze(['Óscar', 'Ana', 'Ñora', 'Nora', 'álvaro'])
    expect(sortList(names, name => name, 'asc')).toEqual(['álvaro', 'Ana', 'Nora', 'Ñora', 'Óscar'])
    expect(sortList(names, name => name, 'desc')).toEqual(['Óscar', 'Ñora', 'Nora', 'Ana', 'álvaro'])
  })

  test('ordena números y nombres de recursos de forma natural', () => {
    expect(sortList([10, -2, 0, 2], value => value, 'asc')).toEqual([-2, 0, 2, 10])
    expect(sortList([10, -2, 0, 2], value => value, 'desc')).toEqual([10, 2, 0, -2])
    expect(sortList(['Sala 10', 'Sala 2', 'Sala 1'], value => value, 'asc'))
      .toEqual(['Sala 1', 'Sala 2', 'Sala 10'])
  })

  test.each(['asc', 'desc'] as const)('deja valores vacíos al final en orden %s', direction => {
    const values: SortValue[] = [null, 2, undefined, '', Number.NaN, 1]
    const expected = direction === 'asc' ? [1, 2] : [2, 1]
    expect(sortList(values, value => value, direction)).toEqual([...expected, null, undefined, '', Number.NaN])
  })

  test.each(['asc', 'desc'] as const)('conserva empates, referencias y entrada en orden %s', direction => {
    // Congelar la entrada detecta una regresión que intente ordenar el arreglo original.
    const first = { id: 1, name: 'Ana' }
    const second = { id: 2, name: 'ana' }
    const source = Object.freeze([first, second])
    const result = sortList(source, item => item.name, direction)
    expect(result).toEqual([first, second])
    expect(result).not.toBe(source)
    expect(result[0]).toBe(first)
    expect(result[1]).toBe(second)
    expect(source).toEqual([first, second])
    expect(sortList([], () => '', direction)).toEqual([])
  })
})

describe('dateSortValue', () => {
  // Zonas explícitas y resultados conocidos evitan depender del reloj o la zona horaria del equipo.
  test.each(['1970-01-01T00:00:00Z', '1969-12-31T21:00:00-03:00'])('normaliza el instante %s', value => {
    expect(dateSortValue(value)).toBe(0)
  })

  test.each([null, undefined, ''])('representa ausencia de fecha (%s) como null', value => {
    expect(dateSortValue(value)).toBeNull()
  })

  test('representa una fecha inválida como NaN', () => {
    expect(dateSortValue('fecha-invalida')).toBeNaN()
  })

  test('permite ordenar instantes y dejar fechas ausentes o inválidas al final', () => {
    const values = [null, '2026-10-20T01:00:00-03:00', 'invalid', '2026-10-20T03:00:00Z']
    expect(sortList(values, dateSortValue, 'asc'))
      .toEqual([values[3], values[1], null, 'invalid'])
  })
})
