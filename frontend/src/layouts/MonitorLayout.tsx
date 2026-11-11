/**
 * HuellApp · Estructura de las pantallas del monitor.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Componer la navegación del monitor y el contenido de su ruta activa.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Reutiliza la estructura visual del sitio para la experiencia personal.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 *
 * NOTAS DE IMPLEMENTACIÓN
 * ------------------------------------------------------------
 * HuellApp
 * Layout exclusivo para MONITOR.
 *
 * OBJETIVO
 * ------------------------------------------------------------
 * Mantener una experiencia propia para el monitor,
 * pero utilizando la misma estructura visual general
 * de HuellApp.
 *
 * El monitor solamente visualiza:
 * - Inicio.
 * - Mis instancias.
 *
 * No visualiza mantenedores administrativos.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La navegación visible no reemplaza las restricciones
 * de RoleRoute ni la autorización implementada en FastAPI.
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
        <SectionOutlet />
      </main>
    </div>
  )
}


export default MonitorLayout
