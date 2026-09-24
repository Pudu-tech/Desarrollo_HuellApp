/**
 * HuellAPP
 * Layout principal para:
 * - SUPERADMIN
 * - DIRECTIVA
 * - COORDINADOR
 *
 * La navegación se filtra según role_code.
 *
 * IMPORTANTE
 * ------------------------------------------------------------
 * La seguridad real continúa en el backend.
 * Ocultar un enlace no equivale a autorizar una operación.
 */

import { Link, Outlet, useNavigate } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

function AppLayout() {
  const navigate = useNavigate()
  const { user, logout } = useAuth()

  const roleCode = user?.role_code

  const isAdministrativeRole =
    roleCode === 'SUPERADMIN'
    || roleCode === 'DIRECTIVA'

  const canManageAssignments =
    roleCode === 'SUPERADMIN'
    || roleCode === 'DIRECTIVA'
    || roleCode === 'COORDINADOR'

  const handleLogout = async () => {
    await logout()
    navigate('/', { replace: true })
  }

  return (
    <div>
      <header>
        <h1>HuellAPP</h1>

        <p>
          Usuario: {user?.email}
        </p>

        <p>
          Rol: {roleCode}
        </p>

        <button
          type="button"
          onClick={handleLogout}
        >
          Cerrar sesión
        </button>
      </header>

      <nav aria-label="Navegación principal">
        <ul>
          <li>
            <Link to="/app/inicio">
              Inicio
            </Link>
          </li>

          {isAdministrativeRole && (
            <>
              <li>
                <Link to="/app/usuarios">
                  Usuarios
                </Link>
              </li>

              <li>
                <Link to="/app/colegios">
                  Colegios
                </Link>
              </li>

              <li>
                <Link to="/app/cursos">
                  Cursos
                </Link>
              </li>

              <li>
                <Link to="/app/salas">
                  Salas
                </Link>
              </li>
            </>
          )}

          {canManageAssignments && (
            <li>
              <Link to="/app/asignaciones">
                Asignaciones
              </Link>
            </li>
          )}

          {roleCode === 'SUPERADMIN' && (
            <li>
              <Link to="/app/auditoria">
                Auditoría
              </Link>
            </li>
          )}
        </ul>
      </nav>

      <hr />

      <main>
        <Outlet />
      </main>
    </div>
  )
}

export default AppLayout
