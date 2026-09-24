/**
 * HuellAPP
 * Página base: Cursos.
 *
 * Visible únicamente para roles administrativos autorizados
 * desde el frontend. El backend mantiene la autorización real.
 */

function CursosPage() {
  return (
    <section>
      <h2>Cursos</h2>

      <p>Administración de cursos.</p>

      <button type="button">
        Crear curso
      </button>

      <p>
        Próximamente: integración completa con backend.
      </p>
    </section>
  )
}

export default CursosPage
