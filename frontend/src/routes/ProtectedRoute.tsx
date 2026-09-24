/**
 * HuellAPP
 * Guard general para rutas que requieren sesión autenticada.
 */

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
    return <p>Cargando...</p>
  }

  if (!user) {
    return <Navigate to="/" replace />
  }

  return children
}

export default ProtectedRoute
