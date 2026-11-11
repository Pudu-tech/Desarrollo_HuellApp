/**
 * HuellApp · Aviso de acceso no disponible.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Informar que la sección no está habilitada para el rol del usuario.
 * - Ofrecer un enlace de regreso al inicio correspondiente.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Los monitores regresan a /app/monitor; los demás roles, a /app/inicio.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Esta pantalla es informativa. La autorización de los datos y las
 * operaciones corresponde al backend.
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
