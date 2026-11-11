/**
 * HuellApp · Control de navegación por rol.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Permitir la ruta a los roles previstos o mostrar acceso no disponible.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Usa el rol del usuario recibido por el contexto autenticado.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 *
 * NOTAS DE IMPLEMENTACIÓN
 * ------------------------------------------------------------
 * HuellApp
 * Guard de rutas basado en rol.
 *
 * RESPONSABILIDAD
 * ------------------------------------------------------------
 * Restringir visualmente rutas del frontend según role_code.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Este guard NO reemplaza la autorización del backend.
 * FastAPI continúa validando permisos en cada endpoint.
 */
import LoadingIndicator from '../components/LoadingIndicator'


import type { ReactNode } from 'react'

import { Navigate } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'
import type { RoleCode } from '../utils/roles'

interface RoleRouteProps {
  allowedRoles: RoleCode[]
  children: ReactNode
}

function RoleRoute({
  allowedRoles,
  children,
}: RoleRouteProps) {
  const { user, loading } = useAuth()

  if (loading) {
    return <LoadingIndicator />
  }

  if (!user) {
    return <Navigate to="/" replace />
  }

  if (
    !allowedRoles.includes(
      user.role_code as RoleCode,
    )
  ) {
    return (
      <Navigate
        to="/app/acceso-denegado"
        replace
      />
    )
  }

  return children
}

export default RoleRoute
