/**
 * HuellApp · Instancias propias del monitor.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Abrir el listado personal con el contexto de navegación del monitor.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Reutiliza MisParticipacionesPage mediante su propiedad monitor.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import MisParticipacionesPage from './MisParticipacionesPage'
export default function MonitorAsignacionesPage() { return <MisParticipacionesPage monitor /> }
