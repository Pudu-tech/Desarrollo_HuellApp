import LoadingIndicator from '../components/LoadingIndicator'
/**
 * HuellApp
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
    return <LoadingIndicator />
  }

  if (!user) {
    return <Navigate to="/" replace />
  }

  return children
}

export default ProtectedRoute
