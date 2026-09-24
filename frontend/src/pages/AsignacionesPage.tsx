/**
 * HuellAPP
 * Página de gestión de asignaciones.
 *
 * Visible para:
 * - SUPERADMIN
 * - DIRECTIVA
 * - COORDINADOR
 *
 * El backend determina qué operaciones puede ejecutar cada rol.
 */

import { Link } from 'react-router-dom'

function AsignacionesPage() {
  return (
    <section>
      <h2>Asignaciones</h2>

      <p>
        Gestión general de asignaciones.
      </p>

      <button type="button">
        Crear asignación
      </button>

      <p>
        Ejemplo:
      </p>

      <Link to="/app/asignaciones/demo">
        Abrir detalle de prueba
      </Link>
    </section>
  )
}

export default AsignacionesPage
