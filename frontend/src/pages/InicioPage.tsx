/**
 * HuellAPP
 * Inicio de la zona administrativa/operativa.
 *
 * Visible para:
 * - SUPERADMIN
 * - DIRECTIVA
 * - COORDINADOR
 */

import { useAuth } from '../contexts/AuthContext'


function InicioPage() {
  const { user } = useAuth()

  const displayName = user
    ? [
        user.nombres,
        user.apellido_paterno,
      ]
        .filter(Boolean)
        .join(' ')
    : ''


  return (
    <section>
      <h2>
        Inicio
      </h2>

      <p>
        Bienvenido {displayName}.
      </p>

      <p>
        Rol actual: {user?.role_code}
      </p>
    </section>
  )
}


export default InicioPage