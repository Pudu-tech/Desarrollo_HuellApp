/**
 * HuellApp · Destino inicial según rol.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Redirigir al inicio correspondiente al usuario autenticado.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Resuelve el acceso a la raíz de la zona privada.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 *
 * NOTAS DE IMPLEMENTACIÓN
 * ------------------------------------------------------------
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
import LoadingIndicator from '../components/LoadingIndicator'


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
