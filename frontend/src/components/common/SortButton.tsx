/**
 * HuellApp · Control común de ordenación.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Mostrar las flechas del orden vigente y comunicar el cambio solicitado.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Anuncia la siguiente acción a lectores de pantalla; el consumidor ordena los datos.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import type { SortState } from '../../utils/listSort'
import '../../styles/list-sort.css'

export interface SortButtonProps<K extends string> {
  label: string; column: K; sort: SortState<K>; onSort: (key: K) => void
}

/** Muestra el orden activo; el callback decide cómo ordenar o consultar los datos. */
export default function SortButton<K extends string>({ label, column, sort, onSort }: SortButtonProps<K>) {
  const active = sort.key === column
  const next = active && sort.direction === 'asc' ? 'descendente' : 'ascendente'
  return <button type="button" className="list-sort-button" onClick={() => onSort(column)} aria-label={`Ordenar ${label.toLocaleLowerCase('es')}: ${next}`}>
    {label}<span aria-hidden="true"><span className={active && sort.direction === 'asc' ? 'is-active' : ''}>↑</span><span className={active && sort.direction === 'desc' ? 'is-active' : ''}>↓</span></span>
  </button>
}
