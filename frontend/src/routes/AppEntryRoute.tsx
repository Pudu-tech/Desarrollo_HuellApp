import LoadingIndicator from '../components/LoadingIndicator'
/**
 * HuellApp
 * Redirección inicial según rol.
 *
 * FLUJO
 * ------------------------------------------------------------
 * SUPERADMIN / DIRECTIVA / COORDINADOR
 *     -> /app/inicio
 *
 * MONITOR
 *     -> /app/monitor
 */

import { Navigate } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

function AppEntryRoute() {
  const { user, loading } = useAuth()

  if (loading) {
    return <LoadingIndicator />
  }

  if (!user) {
    return <Navigate to="/" replace />
  }

  if (user.role_code === 'MONITOR') {
    return (
      <Navigate
        to="/app/monitor"
        replace
      />
    )
  }

  return (
    <Navigate
      to="/app/inicio"
      replace
    />
  )
}

export default AppEntryRoute
