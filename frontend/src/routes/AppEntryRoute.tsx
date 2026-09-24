/**
 * HuellAPP
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
    return <p>Cargando...</p>
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
