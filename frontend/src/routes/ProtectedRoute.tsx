/**
 * HuellApp · Control de sesión en las rutas privadas.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Esperar la restauración de sesión y redirigir al ingreso cuando falta usuario.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Protección de navegación mediante el contexto de autenticación.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import LoadingIndicator from '../components/LoadingIndicator'


import type { ReactNode } from 'react'

import { Navigate } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

interface ProtectedRouteProps {
  children: ReactNode
}

function ProtectedRoute({
  children,
}: ProtectedRouteProps) {
  const { user, loading } = useAuth()

  if (loading) {
    return <LoadingIndicator />
  }

  if (!user) {
    return <Navigate to="/" replace />
  }

  return children
}

export default ProtectedRoute
