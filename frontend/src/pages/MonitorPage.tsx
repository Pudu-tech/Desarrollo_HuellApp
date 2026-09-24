/**
 * HuellAPP
 * Página principal exclusiva del rol MONITOR.
 *
 * OBJETIVO
 * ------------------------------------------------------------
 * Servir como punto de entrada personal del monitor.
 *
 * Próximamente podrá mostrar:
 * - asignaciones pendientes;
 * - participaciones por aceptar/rechazar;
 * - próximas actividades;
 * - asistencias pendientes de informar.
 */

import { Link } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

function MonitorPage() {
  const { user } = useAuth()

  return (
    <section>
      <h2>Mi espacio</h2>

      <p>
        Bienvenido, {user?.email}.
      </p>

      <p>
        Desde aquí podrás revisar tus actividades
        y registrar las acciones asociadas a tu participación.
      </p>

      <Link to="/app/monitor/asignaciones">
        Ver mis asignaciones
      </Link>
    </section>
  )
}

export default MonitorPage
