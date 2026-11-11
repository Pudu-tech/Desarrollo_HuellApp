/**
 * HuellApp · Ruta no encontrada.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Informar que la dirección solicitada no corresponde a una página disponible.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Ofrece navegación de regreso desde una ruta inexistente.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */

import { Link } from 'react-router-dom'

function NotFoundPage() {
  return (
    <main>
      <h1>Página no encontrada</h1>

      <Link to="/app">
        Volver a HuellApp
      </Link>
    </main>
  )
}

export default NotFoundPage
