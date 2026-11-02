import LoadingIndicator from '../components/LoadingIndicator'
import {
  type ChangeEvent,
  type FormEvent,
  useEffect,
  useId,
  useState,
} from 'react'
import {
  Link,
  Navigate,
  useNavigate,
} from 'react-router-dom'

import { useAuth } from '../contexts/AuthContext'

import '../styles/login.css'

import carrusel1 from '../assets/Carrusel_1.jpg'
import carrusel2 from '../assets/Carrusel_2.jpg'
import carrusel3 from '../assets/Carrusel_3.jpg'

// Vite procesa las imágenes locales y genera sus rutas para producción.
const fotos = [
  { src: carrusel1, alt: 'Fundación Huella: fotografía 1' },
  { src: carrusel2, alt: 'Fundación Huella: fotografía 2' },
  { src: carrusel3, alt: 'Fundación Huella: fotografía 3' },
]

interface Credentials {
  email: string
  password: string
}

interface EyeIconProps {
  isVisible: boolean
}

function MailIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m4 7 8 6 8-6" />
    </svg>
  )
}

function LockIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="5" y="10" width="14" height="11" rx="2" />
      <path d="M8 10V7a4 4 0 0 1 8 0v3" />
    </svg>
  )
}

function EyeIcon({ isVisible }: EyeIconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6Z" />
      <circle cx="12" cy="12" r="2.5" />

      {!isVisible && (
        <path d="m4 4 16 16" />
      )}
    </svg>
  )
}

function ArrowIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path d="m9 18 6-6-6-6" />
    </svg>
  )
}

function ShieldIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M12 3 5 6v5c0 4.5 2.8 8.4 7 10 4.2-1.6 7-5.5 7-10V6l-7-3Z" />
      <path d="m9.2 12 1.8 1.8 3.8-4" />
    </svg>
  )
}

function validateCredentials(
  credentials: Credentials,
): string {
  const email = credentials.email.trim()

  if (!email || !credentials.password) {
    return 'Ingresa tu correo electrónico y contraseña.'
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return 'Ingresa un correo electrónico válido.'
  }

  return ''
}

// Componente independiente: mantiene el estado de la fotografía visible.
function LoginCarousel() {
  const [actual, setActual] = useState(0)
  const [pausado, setPausado] = useState(false)

  useEffect(() => {
    // Respeta la pausa y la preferencia del sistema de reducir movimiento.
    if (pausado || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      return
    }

    // Cada cambio, incluso manual, inicia una nueva espera de quince segundos.
    const temporizador = window.setTimeout(() => {
      setActual((indice) => (indice + 1) % fotos.length)
    }, 15000)

    // Evita temporizadores duplicados y actualizaciones al salir del login.
    return () => window.clearTimeout(temporizador)
  }, [actual, pausado])

  const cambiar = (paso: number) => {
    // El módulo permite avanzar de la última foto a la primera y viceversa.
    setActual((indice) =>
     (indice + paso + fotos.length) % fotos.length
    )
  }

  // React muestra este contenido donde se inserta <LoginCarousel />.
  return (
    <section
      className="login-carousel"
      aria-roledescription="carrusel"
      aria-label="Fotografías de Fundación Huella"
    >
      {/* Las fotos superpuestas permiten fundir la anterior con la siguiente. */}
      {fotos.map((foto, indice) => (
        <img
          key={foto.src}
          src={foto.src}
          alt={indice === actual ? foto.alt : ''}
          aria-hidden={indice !== actual}
          className={`login-carousel__image${indice === actual ? ' login-carousel__image--active' : ''}`}
        />
      ))}
      <div className="login-carousel__controls">
        <button
          type="button"
          onClick={() => cambiar(-1)}
          aria-label="Fotografía anterior"
        >
          ←
        </button>
        {/* Evita anuncios automáticos cada quince segundos al lector de pantalla. */}
        <span>
          {actual + 1} / {fotos.length}
        </span>
        <button
          type="button"
          onClick={() => cambiar(1)}
          aria-label="Fotografía siguiente"
        >
          →
        </button>
        {/* Permite detener y reanudar la reproducción automática. */}
        <button
          type="button"
          onClick={() => setPausado((valor) => !valor)}
          aria-label={pausado ? 'Reanudar carrusel' : 'Pausar carrusel'}
          aria-pressed={pausado}
        >
          {pausado ? '▶' : 'Ⅱ'}
        </button>
      </div>
    </section>
  )
}

function LoginPage() {
  const navigate = useNavigate()
  const { user, loading, login } = useAuth()

  const emailHelpId = useId()
  const passwordHelpId = useId()
  const statusId = useId()

  const [credentials, setCredentials] =
    useState<Credentials>({
      email: '',
      password: '',
    })

  const [error, setError] = useState('')
  const [isLoading, setIsLoading] =
    useState(false)
  const [showPassword, setShowPassword] =
    useState(false)

  if (loading) {
    return (
      <main className="huella-login-page">
        <section className="huella-login-access">
          <LoadingIndicator />
        </section>
      </main>
    )
  }

  if (user) {
    return <Navigate to="/app" replace />
  }

  const handleChange = (
    event: ChangeEvent<HTMLInputElement>,
  ) => {
    const { name, value } = event.target

    setCredentials((currentCredentials) => ({
      ...currentCredentials,
      [name]: value,
    }))

    if (error) {
      setError('')
    }
  }

  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

    const validationError =
      validateCredentials(credentials)

    if (validationError) {
      setError(validationError)
      return
    }

    setIsLoading(true)
    setError('')

    try {
      await login(
        credentials.email.trim(),
        credentials.password,
      )

      navigate('/app', {
        replace: true,
      })
    } catch (loginError) {
      setError(
        loginError instanceof Error
          ? loginError.message
          : 'No fue posible iniciar sesión. Inténtalo nuevamente.',
      )
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <main className="huella-login-page">
      <section
        className="huella-login-story"
        aria-label="Presentación de HuellApp"
      >
        <div className="huella-login-story__content">
          <p className="huella-login-story__eyebrow">
            HuellApp
          </p>

          {/* Monta el carrusel en el panel izquierdo, debajo de HuellApp. */}
          <LoginCarousel />
        </div>

        <div
          className="huella-login-art"
          aria-hidden="true"
        >
          <span className="huella-login-art__circle" />

          <span className="huella-login-art__path huella-login-art__path--one" />

          <span className="huella-login-art__path huella-login-art__path--two" />

          <span className="huella-login-art__path huella-login-art__path--three" />
        </div>

        <p className="huella-login-story__footer">
          Educación <span>•</span>
          Personas <span>•</span>
          Comunidad <span>•</span>
          Impacto
        </p>
      </section>

      <section
        className="huella-login-access"
        aria-label="Acceso a HuellApp"
      >
        <div className="huella-login-card">
          <header className="huella-login-card__header">
            <img
              src="/logo-huella.png"
              alt="Fundación Huella Formación y Vocación"
              className="huella-login-card__logo"
            />

            <span
              className="huella-login-card__accent"
              aria-hidden="true"
            />

            <div
              className="huella-login-card__security-icon"
              aria-hidden="true"
            >
              <LockIcon />
            </div>

            <h2>Bienvenido a HuellApp</h2>

            <p>
              Ingresa tus datos para acceder a tu espacio
              de trabajo.
            </p>
          </header>

          <form
            className="huella-login-form"
            onSubmit={handleSubmit}
            noValidate
          >
            <div className="huella-login-field">
              <label htmlFor="huella-email">
                Correo electrónico
              </label>

              <div className="huella-login-field__control">
                <MailIcon />

                <input
                  id="huella-email"
                  name="email"
                  type="email"
                  value={credentials.email}
                  onChange={handleChange}
                  placeholder="tu.correo@fundacionhuella.cl"
                  autoComplete="email"
                  inputMode="email"
                  aria-describedby={
                    error
                      ? statusId
                      : emailHelpId
                  }
                  aria-invalid={Boolean(error)}
                  disabled={isLoading}
                />
              </div>

              <span
                id={emailHelpId}
                className="huella-login-sr-only"
              >
                Usa el correo asociado a tu cuenta
                HuellApp.
              </span>
            </div>

            <div className="huella-login-field">
              <label htmlFor="huella-password">
                Contraseña
              </label>

              <div className="huella-login-field__control">
                <LockIcon />

                <input
                  id="huella-password"
                  name="password"
                  type={
                    showPassword
                      ? 'text'
                      : 'password'
                  }
                  value={credentials.password}
                  onChange={handleChange}
                  placeholder="Ingresa tu contraseña"
                  autoComplete="current-password"
                  aria-describedby={
                    error
                      ? statusId
                      : passwordHelpId
                  }
                  aria-invalid={Boolean(error)}
                  disabled={isLoading}
                />

                <button
                  className="huella-login-field__visibility"
                  type="button"
                  onClick={() =>
                    setShowPassword(
                      (isVisible) =>
                        !isVisible,
                    )
                  }
                  aria-label={
                    showPassword
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña'
                  }
                  aria-pressed={showPassword}
                  disabled={isLoading}
                >
                  <EyeIcon
                    isVisible={showPassword}
                  />
                </button>
              </div>

              <span
                id={passwordHelpId}
                className="huella-login-sr-only"
              >
                Ingresa la contraseña asociada a tu
                cuenta.
              </span>
            </div>

            <div className="huella-login-form__options">
              <Link to="/recuperar-password">
                ¿Olvidaste tu contraseña?
              </Link>
            </div>

            <p
              id={statusId}
              className={`huella-login-status${
                error
                  ? ' huella-login-status--error'
                  : ''
              }`}
              role="status"
              aria-live="polite"
            >
              {error}
            </p>

            <button
              className="huella-login-submit"
              type="submit"
              disabled={isLoading}
            >
              <span>
                {isLoading
                  ? 'Ingresando…'
                  : 'Ingresar'}
              </span>

              {!isLoading && <ArrowIcon />}
            </button>
          </form>

          <footer className="huella-login-card__footer">
            <ShieldIcon />

            <span>
              Acceso exclusivo para usuarios
              autorizados.
            </span>
          </footer>
        </div>

        <div className="huella-login-access__links">
          <a
            href="https://www.fundacionhuella.cl"
            target="_blank"
            rel="noreferrer"
          >
            Visitar Fundación Huella
          </a>

          
        </div>

        <p className="huella-login-access__copyright">
          Fundación Huella · HuellApp
        </p>
      </section>
    </main>
  )
}

export default LoginPage
