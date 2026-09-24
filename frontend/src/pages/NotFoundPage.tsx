/**
 * HuellAPP
 * Página para rutas inexistentes.
 */

import { Link } from 'react-router-dom'

function NotFoundPage() {
  return (
    <main>
      <h1>Página no encontrada</h1>

      <Link to="/app">
        Volver a HuellAPP
      </Link>
    </main>
  )
}

export default NotFoundPage
