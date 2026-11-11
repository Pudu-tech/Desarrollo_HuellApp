/**
 * HuellApp · Indicador de carga compartido.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Mostrar el estado de espera con una presentación común.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Componente reutilizable en páginas y paneles diferidos.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import '../styles/loading-indicator.css'

export default function LoadingIndicator() {
  return <div className="huella-loading" role="status" aria-live="polite">
    <div className="huella-loading-scene" aria-hidden="true">
      <div className="huella-loading-logo">
        <img className="huella-loading-face" src="/logo-huella.png" alt="" width="150" height="150" />
        <img className="huella-loading-back" src="/logo-huella.png" alt="" width="150" height="150" />
      </div>
      <div className="huella-loading-shadow" />
    </div>
    <span>Cargando…</span>
  </div>
}
