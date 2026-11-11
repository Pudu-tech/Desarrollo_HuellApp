/**
 * HuellApp · Estructura de las pantallas de gestión.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Componer la barra lateral y el contenido de la ruta administrativa activa.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Estructura compartida para SUPERADMIN, DIRECTIVA y COORDINADOR.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 *
 * NOTAS DE IMPLEMENTACIÓN
 * ------------------------------------------------------------
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
  useNavigate,
} from 'react-router-dom'

import Sidebar from '../components/navigation/Sidebar'
import SectionOutlet from '../components/navigation/SectionOutlet'

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
        <SectionOutlet />
      </main>
    </div>
  )
}


export default AppLayout
