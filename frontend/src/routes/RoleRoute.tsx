/**
 * HuellAPP
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
    return <p>Cargando...</p>
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
