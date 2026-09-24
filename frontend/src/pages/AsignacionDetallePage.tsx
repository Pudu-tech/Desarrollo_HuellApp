/**
 * HuellAPP
 * Detalle de asignación para roles de gestión.
 */

import { Link, useParams } from 'react-router-dom'

function AsignacionDetallePage() {
  const { asignacionId } = useParams()

  return (
    <section>
      <h2>Detalle de asignación</h2>

      <p>
        ID recibido: {asignacionId}
      </p>

      <p>
        Próximamente: participantes, asistencia,
        historial y acciones permitidas por rol.
      </p>

      <Link to="/app/asignaciones">
        Volver
      </Link>
    </section>
  )
}

export default AsignacionDetallePage
