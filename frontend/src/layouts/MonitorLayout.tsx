/**
 * HuellAPP
 * Layout exclusivo para MONITOR.
 *
 * OBJETIVO
 * ------------------------------------------------------------
 * Mantener una experiencia propia para el monitor,
 * pero utilizando la misma estructura visual general
 * de HuellAPP.
 *
 * El monitor solamente visualiza:
 * - Inicio.
 * - Mis asignaciones.
 *
 * No visualiza mantenedores administrativos.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La navegación visible no reemplaza las restricciones
 * de RoleRoute ni la autorización implementada en FastAPI.
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


function MonitorLayout() {
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


export default MonitorLayout