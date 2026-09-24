/**
 * HuellAPP
 * Página base: Colegios.
 *
 * Visible únicamente para roles administrativos autorizados
 * desde el frontend. El backend mantiene la autorización real.
 */

function ColegiosPage() {
  return (
    <section>
      <h2>Colegios</h2>

      <p>Administración de colegios.</p>

      <button type="button">
        Crear colegio
      </button>

      <p>
        Próximamente: integración completa con backend.
      </p>
    </section>
  )
}

export default ColegiosPage
