/**
 * HuellAPP
 * Página base de auditoría.
 *
 * En este paquete se deja visible únicamente para SUPERADMIN.
 *
 * Si posteriormente el backend define un permiso explícito para
 * otros roles, la visibilidad del frontend puede ampliarse.
 */

function AuditoriaPage() {
  return (
    <section>
      <h2>Auditoría</h2>

      <p>
        Consulta de eventos registrados en audit_logs.
      </p>

      <p>
        Esta pantalla será de solo lectura.
      </p>
    </section>
  )
}

export default AuditoriaPage
