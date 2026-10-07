/**
 * HuellApp
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

  const displayName = [
    user.nombres,
    user.apellido_paterno,
  ]
    .filter(Boolean)
    .join(' ')


  return (
    <div className="app-shell">
      <Sidebar
        displayName={displayName}
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