/**
 * HuellApp · Estado de ordenación de listados.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Conservar la columna y dirección elegidas y ordenar una copia de los datos cargados.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Nueva columna en ascendente; repetirla alterna la dirección.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useState } from 'react'
import { sortList, type SortState, type SortDirection, type SortValue } from '../utils/listSort'

/** Inicia el orden y expone controles reutilizables por tablas y selectores. */
export function useListSort<K extends string>(initialKey: K, direction: SortDirection = 'asc') {
  const [sort, setSort] = useState<SortState<K>>({ key: initialKey, direction })
  /** Una columna nueva comienza ascendente; repetir la misma alterna la dirección. */
  function toggle(key: K) {
    setSort((previous) => ({ key, direction: previous.key === key && previous.direction === 'asc' ? 'desc' : 'asc' }))
  }
  /** Cada columna define cómo extraer su valor; devuelve una copia ordenada. */
  function order<T>(items: readonly T[], values: Record<K, (item: T) => SortValue>) {
    return sortList(items, values[sort.key], sort.direction)
  }
  return { sort, toggle, order, setSort }
}
