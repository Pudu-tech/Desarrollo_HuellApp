/**
 * HuellApp · Comparación común de listados.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Ordenar nombres, números y fechas sin modificar el arreglo de origen.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Comparación natural en español, empates estables y valores vacíos al final.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
export type SortDirection = 'asc' | 'desc'
export type SortState<K extends string = string> = { key: K; direction: SortDirection }
export type SortValue = string | number | null | undefined
// Ignora diferencias de mayúsculas y acentos y coloca, por ejemplo, Sala 2 antes de Sala 10.
const collator = new Intl.Collator('es', { sensitivity: 'base', numeric: true })

/** Orden estable sin mutar la fuente; los valores vacíos siempre quedan al final. */
export function sortList<T>(items: readonly T[], value: (item: T) => SortValue, direction: SortDirection): T[] {
  const compare = (a: SortValue, b: SortValue) => {
    const missingA = a == null || a === '' || (typeof a === 'number' && Number.isNaN(a))
    const missingB = b == null || b === '' || (typeof b === 'number' && Number.isNaN(b))
    if (missingA || missingB) return missingA === missingB ? 0 : missingA ? 1 : -1
    const result = typeof a === 'number' && typeof b === 'number' ? a - b : collator.compare(String(a), String(b))
    return direction === 'asc' ? result : -result
  }
  // Calcula cada valor una vez y conserva el orden original cuando hay empates.
  return items.map((item, index) => ({ item, index, value: value(item) }))
    .sort((a, b) => compare(a.value, b.value) || a.index - b.index)
    .map(({ item }) => item)
}

/** Convierte fechas a tiempo numérico; sortList trata las fechas inválidas como vacías. */
export const dateSortValue = (value: string | null | undefined) => value ? Date.parse(value) : null
