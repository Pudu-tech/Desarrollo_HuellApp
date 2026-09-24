/**
 * HuellAPP
 * Página base: Usuarios.
 *
 * Visible únicamente para roles administrativos autorizados
 * desde el frontend. El backend mantiene la autorización real.
 */

function UsuariosPage() {
  return (
    <section>
      <h2>Usuarios</h2>

      <p>Administración de usuarios.</p>

      <button type="button">
        Crear usuario
      </button>

      <p>
        Próximamente: integración completa con backend.
      </p>
    </section>
  )
}

export default UsuariosPage
