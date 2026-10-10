import '../styles/loading-indicator.css'

export default function LoadingIndicator() {
  return <div className="huella-loading" role="status" aria-live="polite">
    <div className="huella-loading-scene" aria-hidden="true">
      <div className="huella-loading-logo">
        {[0, 1, 2, 3, 4, 5].map((layer) => <img key={layer} className={`huella-loading-layer huella-loading-layer--${layer}`} src="/logo-huella.png" alt="" width="120" height="120" />)}
        <img className="huella-loading-face" src="/logo-huella.png" alt="" width="120" height="120" />
        <img className="huella-loading-back" src="/logo-huella.png" alt="" width="120" height="120" />
      </div>
      <div className="huella-loading-shadow" />
    </div>
    <span>Cargando…</span>
  </div>
}
