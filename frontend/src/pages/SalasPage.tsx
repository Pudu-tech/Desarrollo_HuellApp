/**
 * HuellAPP
 * Página base: Salas.
 *
 * Visible únicamente para roles administrativos autorizados
 * desde el frontend. El backend mantiene la autorización real.
 */

function SalasPage() {
  return (
    <section>
      <h2>Salas</h2>

      <p>Administración de salas.</p>

      <button type="button">
        Crear sala
      </button>

      <p>
        Próximamente: integración completa con backend.
      </p>
    </section>
  )
}

export default SalasPage
