/**
 * HuellAPP
 * Página base de asignaciones personales del MONITOR.
 *
 * PENDIENTE
 * ------------------------------------------------------------
 * Conectar con endpoints de asignaciones para:
 * - listar participaciones propias;
 * - aceptar/rechazar;
 * - registrar asistencia propia;
 * - consultar detalle.
 */

import { Link } from 'react-router-dom'

function MonitorAsignacionesPage() {
  return (
    <section>
      <h2>Mis asignaciones</h2>

      <p>
        Aquí se mostrarán únicamente las asignaciones
        relacionadas con el usuario autenticado.
      </p>

      <Link to="/app/monitor/asignaciones/demo">
        Abrir detalle de prueba
      </Link>
    </section>
  )
}

export default MonitorAsignacionesPage
