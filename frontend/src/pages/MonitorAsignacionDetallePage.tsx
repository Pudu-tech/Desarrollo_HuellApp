/**
 * HuellAPP
 * Detalle personal de una asignación para MONITOR.
 *
 * Próximamente incluirá:
 * - información de actividad;
 * - estado de participación;
 * - aceptar/rechazar;
 * - registro de asistencia propia.
 */

import { Link, useParams } from 'react-router-dom'

function MonitorAsignacionDetallePage() {
  const { asignacionId } = useParams()

  return (
    <section>
      <h2>Detalle de mi asignación</h2>

      <p>
        ID recibido: {asignacionId}
      </p>

      <button type="button">
        Aceptar participación
      </button>

      {' '}

      <button type="button">
        Rechazar participación
      </button>

      <p>
        El registro de asistencia se conectará después
        con geolocalización y backend.
      </p>

      <Link to="/app/monitor/asignaciones">
        Volver a mis asignaciones
      </Link>
    </section>
  )
}

export default MonitorAsignacionDetallePage
