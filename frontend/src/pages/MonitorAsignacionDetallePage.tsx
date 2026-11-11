/**
 * HuellApp · Detalle personal del monitor.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Abrir la participación propia con el contexto de navegación del monitor.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Reutiliza MiParticipacionPage mediante su propiedad monitor.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import MiParticipacionPage from './MiParticipacionPage'
export default function MonitorAsignacionDetallePage() { return <MiParticipacionPage monitor /> }
