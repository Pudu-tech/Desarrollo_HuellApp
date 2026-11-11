/**
 * HuellApp · Encabezado de tabla ordenable.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Combinar el botón de ordenación con la semántica del encabezado de columna.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Expone el estado actual mediante aria-sort.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import SortButton, { type SortButtonProps } from './SortButton'

/** Expone a tecnologías de asistencia el orden actual de esta columna. */
export default function SortableHeader<K extends string>(props: SortButtonProps<K>) {
  return <th scope="col" aria-sort={props.sort.key !== props.column ? 'none' : props.sort.direction === 'asc' ? 'ascending' : 'descending'}><SortButton {...props} /></th>
}
