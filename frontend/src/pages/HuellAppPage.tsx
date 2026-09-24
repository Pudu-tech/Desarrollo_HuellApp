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
      <h1>HuellAPP</h1>

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