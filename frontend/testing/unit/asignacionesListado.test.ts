import { describe, expect, test } from 'vitest'
import { colegiosDisponibles, ordenarPorFecha } from '../../src/utils/asignacionesListado'

describe('ordenarPorFecha', () => {
  test.each([
    { direction: 'asc', expected: ['old', 'early', 'late'] },
    { direction: 'desc', expected: ['late', 'early', 'old'] },
  ] as const)('ordena por fecha y desempata por hora en orden $direction', ({ direction, expected }) => {
    // Preparar → ejecutar → comprobar: cada caso crea datos propios y no comparte estado mutable.
    const items = Object.freeze([
      { id: 'late', fecha: '2026-10-20', hora_inicio: '11:00' },
      { id: 'old', fecha: '2025-12-31', hora_inicio: '18:00' },
      { id: 'early', fecha: '2026-10-20', hora_inicio: '08:00' },
    ])
    const result = ordenarPorFecha(items, direction)
    expect(result.map(item => item.id)).toEqual(expected)
    expect(items.map(item => item.id)).toEqual(['late', 'old', 'early'])
    expect(result.find(item => item.id === 'late')).toBe(items[0])
  })

  test.each(['asc', 'desc'] as const)('conserva empates y admite listas vacías en orden %s', direction => {
    const items = [
      { id: 1, fecha: '2026-10-20', hora_inicio: '08:00' },
      { id: 2, fecha: '2026-10-20', hora_inicio: '08:00' },
    ]
    expect(ordenarPorFecha(items, direction).map(item => item.id)).toEqual([1, 2])
    expect(ordenarPorFecha([], direction)).toEqual([])
  })
})

describe('colegiosDisponibles', () => {
  test('excluye inactivos y eliminados sin alterar el catálogo histórico', () => {
    const current = { id: 'current', activo: true, deleted_at: null }
    const schools = Object.freeze([
      current,
      { id: 'inactive', activo: false, deleted_at: null },
      { id: 'deleted', activo: true, deleted_at: '2026-10-20' },
      { id: 'both', activo: false, deleted_at: '2026-10-20' },
    ])
    const result = colegiosDisponibles(schools)
    expect(result).toEqual([current])
    expect(result[0]).toBe(current)
    expect(schools).toHaveLength(4)
  })

  test('incluye registros sin estado explícito o con fecha de eliminación vacía', () => {
    const schools = [{ activo: undefined }, { activo: true, deleted_at: '' }]
    expect(colegiosDisponibles(schools)).toEqual(schools)
  })

  test('admite un catálogo vacío', () => {
    expect(colegiosDisponibles([])).toEqual([])
  })
})
