/**
 * HuellAPP
 * Layout principal para:
 * - SUPERADMIN
 * - DIRECTIVA
 * - COORDINADOR
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Componer la estructura principal de la aplicación.
 * - Mostrar el sidebar administrativo.
 * - Renderizar mediante Outlet la página activa.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La visibilidad del menú no constituye autorización.
 * RoleRoute y FastAPI continúan siendo responsables
 * de controlar el acceso real a cada recurso.
 */

import {
  Outlet,
  useNavigate,
} from 'react-router-dom'

import Sidebar from '../components/navigation/Sidebar'

import { useAuth } from '../contexts/AuthContext'

import type {
  AppRole,
} from '../types/navigation'

import '../styles/app-layout.css'

function AppLayout() {
  const navigate = useNavigate()

  const {
    user,
    logout,
  } = useAuth()

  /**
   * Finaliza la sesión y devuelve al usuario
   * al punto público de entrada de HuellAPP.
   */
  const handleLogout = async () => {
    await logout()

    navigate('/', {
      replace: true,
    })
  }

  if (!user) {
    return null
  }

  const roleCode =
    user.role_code as AppRole

  return (
    <div className="app-shell">
      <Sidebar
        email={user.email}
        role={roleCode}
        onLogout={handleLogout}
      />

      <main className="app-content">
        <Outlet />
      </main>
    </div>
  )
}

export default AppLayout