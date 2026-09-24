/**
 * HuellAPP
 * Layout exclusivo para MONITOR.
 *
 * OBJETIVO
 * ------------------------------------------------------------
 * Separar la experiencia del monitor de la administración.
 *
 * El monitor no visualiza mantenedores administrativos.
 * Su navegación se concentra en:
 * - inicio personal;
 * - sus asignaciones;
 * - participación;
 * - asistencia.
 */

import { Link, Outlet, useNavigate } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

function MonitorLayout() {
  const navigate = useNavigate()
  const { user, logout } = useAuth()

  const handleLogout = async () => {
    await logout()
    navigate('/', { replace: true })
  }

  return (
    <div>
      <header>
        <h1>HuellAPP</h1>

        <p>Espacio Monitor</p>

        <p>
          Usuario: {user?.email}
        </p>

        <button
          type="button"
          onClick={handleLogout}
        >
          Cerrar sesión
        </button>
      </header>

      <nav aria-label="Navegación Monitor">
        <ul>
          <li>
            <Link to="/app/monitor">
              Inicio
            </Link>
          </li>

          <li>
            <Link to="/app/monitor/asignaciones">
              Mis asignaciones
            </Link>
          </li>
        </ul>
      </nav>

      <hr />

      <main>
        <Outlet />
      </main>
    </div>
  )
}

export default MonitorLayout
