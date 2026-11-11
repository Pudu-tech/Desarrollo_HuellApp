/**
 * HuellApp · Vista básica de la sesión.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Mostrar correo y rol del usuario y ofrecer el cierre de sesión.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Tras cerrar sesión redirige a la raíz del sitio.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { useNavigate } from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

function HuellAppPage() {
  const navigate = useNavigate()
  const { user, logout } = useAuth()

  const handleLogout = async () => {
    await logout()
    navigate('/', { replace: true })
  }

  return (
    <main>
      <h1>HuellApp</h1>

      <p>
        Usuario: {user?.email}
      </p>

      <p>
        Rol: {user?.role_code}
      </p>

      <button
        type="button"
        onClick={handleLogout}
      >
        Cerrar sesión
      </button>
    </main>
  )
}

export default HuellAppPage