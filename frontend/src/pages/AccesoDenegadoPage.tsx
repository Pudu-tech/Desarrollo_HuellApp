/**
 * HuellAPP
 * Página mostrada cuando un usuario autenticado intenta
 * acceder a una ruta no habilitada para su rol.
 */

import { Link } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

function AccesoDenegadoPage() {
  const { user } = useAuth()

  const home =
    user?.role_code === 'MONITOR'
      ? '/app/monitor'
      : '/app/inicio'

  return (
    <main>
      <h1>Acceso no disponible</h1>

      <p>
        Tu rol no tiene acceso a esta sección.
      </p>

      <Link to={home}>
        Volver al inicio
      </Link>
    </main>
  )
}

export default AccesoDenegadoPage
