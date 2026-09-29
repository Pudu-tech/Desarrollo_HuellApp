/**
 * HuellAPP
 * Página para establecer la contraseña inicial de un usuario invitado.
 *
 * FLUJO
 * ------------------------------------------------------------
 * 1. SUPERADMIN o DIRECTIVA crea e invita al usuario.
 * 2. Supabase Auth envía la invitación mediante Brevo.
 * 3. El usuario abre el enlace recibido.
 * 4. Supabase procesa la invitación y crea una sesión temporal.
 * 5. El usuario establece su contraseña inicial.
 * 6. Cerramos la sesión temporal.
 * 7. Redirigimos al Login.
 * 8. El usuario inicia sesión manualmente con sus credenciales.
 *
 * SECURITY
 * ------------------------------------------------------------
 * - El administrador nunca conoce la contraseña del usuario.
 * - No procesamos manualmente access_token ni refresh_token.
 * - Supabase Auth administra la sesión proveniente de la invitación.
 * - La contraseña se actualiza mediante updateUser().
 * - Después del establecimiento se cierra la sesión local.
 * - No se inicia sesión automáticamente después del cambio.
 */

import {
  useEffect,
  useState,
  type FormEvent,
} from 'react'

import { Link } from 'react-router-dom'

import { supabase } from '../services/supabase'

import '../styles/auth-pages.css'


function EstablecerPasswordPage() {
  const [password, setPassword] =
    useState('')

  const [confirmPassword, setConfirmPassword] =
    useState('')

  const [loading, setLoading] =
    useState(false)

  const [validandoSesion, setValidandoSesion] =
    useState(true)

  const [sesionValida, setSesionValida] =
    useState(false)

  const [error, setError] =
    useState('')

  const [mensaje, setMensaje] =
    useState('')


  /* ==========================================================
     VALIDACIÓN DE SESIÓN DE INVITACIÓN
     ========================================================== */

  useEffect(() => {
    let mounted = true

    /**
     * Comprueba si Supabase creó correctamente una sesión
     * temporal después de procesar el enlace de invitación.
     *
     * No se leen ni manipulan tokens manualmente.
     */
    const validarSesion = async () => {
      const {
        data,
        error: sessionError,
      } = await supabase.auth.getSession()

      if (!mounted) {
        return
      }

      if (sessionError) {
        console.error(
          'Error al validar sesión de invitación:',
          sessionError,
        )

        setSesionValida(false)
        setValidandoSesion(false)

        return
      }

      setSesionValida(
        Boolean(data.session),
      )

      setValidandoSesion(false)
    }

    void validarSesion()


    /**
     * Cuando Supabase procesa correctamente una invitación,
     * puede generar un evento SIGNED_IN al establecer la
     * sesión temporal correspondiente.
     *
     * También aceptamos USER_UPDATED porque puede producirse
     * durante determinados estados del flujo de Auth.
     */
    const {
      data: authListener,
    } = supabase.auth.onAuthStateChange(
      (event, session) => {
        if (!mounted) {
          return
        }

        if (
          (
            event === 'SIGNED_IN'
            || event === 'USER_UPDATED'
          )
          && session
        ) {
          setSesionValida(true)
          setValidandoSesion(false)
        }
      },
    )


    return () => {
      mounted = false

      authListener.subscription.unsubscribe()
    }
  }, [])


  /* ==========================================================
     ESTABLECIMIENTO DE CONTRASEÑA
     ========================================================== */

  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

    if (loading) {
      return
    }

    setError('')
    setMensaje('')


    /* ----------------------------------------------------------
       Validaciones locales
       ---------------------------------------------------------- */

    if (!password || !confirmPassword) {
      setError(
        'Debes completar ambos campos.',
      )

      return
    }


    if (password.length < 8) {
      setError(
        'La contraseña debe tener al menos 8 caracteres.',
      )

      return
    }


    if (password !== confirmPassword) {
      setError(
        'Las contraseñas no coinciden.',
      )

      return
    }


    try {
      setLoading(true)


      /* --------------------------------------------------------
         Confirmar que la sesión siga vigente
         -------------------------------------------------------- */

      const {
        data: sessionData,
        error: sessionError,
      } = await supabase.auth.getSession()

      if (
        sessionError
        || !sessionData.session
      ) {
        setSesionValida(false)

        setError(
          'La invitación ya no es válida o ha expirado.',
        )

        return
      }


      /* --------------------------------------------------------
         Establecer contraseña
         -------------------------------------------------------- */

      const {
        error: updateError,
      } = await supabase.auth.updateUser({
        password,
      })


      if (updateError) {
        console.error(
          'Error al establecer contraseña:',
          updateError,
        )

        const mensajeError =
          updateError.message?.toLowerCase()
          ?? ''


        /* ------------------------------------------------------
           Contraseña débil
           ------------------------------------------------------ */

        if (
          mensajeError.includes('password')
          && mensajeError.includes('weak')
        ) {
          setError(
            'La contraseña no cumple con los '
            + 'requisitos de seguridad.',
          )

          return
        }


        /* ------------------------------------------------------
           Contraseña demasiado corta
           ------------------------------------------------------ */

        if (
          mensajeError.includes('password')
          && (
            mensajeError.includes('characters')
            || mensajeError.includes('length')
          )
        ) {
          setError(
            'La contraseña no cumple con la longitud '
            + 'mínima requerida.',
          )

          return
        }


        /* ------------------------------------------------------
           Sesión o invitación inválida
           ------------------------------------------------------ */

        if (
          mensajeError.includes('session')
          || mensajeError.includes('expired')
          || mensajeError.includes('token')
        ) {
          setSesionValida(false)

          setError(
            'La invitación no es válida o ha expirado.',
          )

          return
        }


        /* ------------------------------------------------------
           Error genérico
           ------------------------------------------------------ */

        setError(
          'No fue posible establecer la contraseña. '
          + 'Solicita una nueva invitación al administrador.',
        )

        return
      }


      /* --------------------------------------------------------
         Operación exitosa
         -------------------------------------------------------- */

      setMensaje(
        'Tu contraseña fue establecida correctamente. '
        + 'Ahora podrás iniciar sesión con tu correo '
        + 'y la contraseña que acabas de crear.',
      )


      /* --------------------------------------------------------
         Cierre de sesión temporal
         --------------------------------------------------------
         Se cierra solamente la sesión del navegador actual.

         Esto evita mantener activa automáticamente la sesión
         utilizada para completar la invitación.
         -------------------------------------------------------- */

      const {
        error: signOutError,
      } = await supabase.auth.signOut({
        scope: 'local',
      })


      if (signOutError) {
        console.error(
          'Error al cerrar sesión de invitación:',
          signOutError,
        )
      }


      /* --------------------------------------------------------
         Redirección limpia al Login
         --------------------------------------------------------
         Utilizamos location.replace() para reiniciar el estado
         de la aplicación y evitar reutilizar la sesión temporal
         almacenada en AuthContext.
         -------------------------------------------------------- */

      setTimeout(() => {
        window.location.replace('/')
      }, 1800)

    } catch (unexpectedError) {
      console.error(
        'Error inesperado al establecer contraseña:',
        unexpectedError,
      )

      setError(
        'Ocurrió un error al establecer la contraseña.',
      )

    } finally {
      setLoading(false)
    }
  }


  /* ==========================================================
     ESTADO: VALIDANDO INVITACIÓN
     ========================================================== */

  if (validandoSesion) {
    return (
      <main className="auth-page">
        <section className="auth-card">

          <header className="auth-header">
            <div className="auth-logo-wrap">
              <img
                src="/logo-huella.png"
                alt="Fundación Huella"
                className="auth-logo"
              />
            </div>

            <p className="auth-brand">
              HuellApp
            </p>
          </header>


          <div className="auth-state-content">
            <h1 className="auth-state-title">
              Validando invitación
            </h1>

            <p className="auth-state-text">
              Estamos comprobando tu enlace de invitación.
            </p>
          </div>

        </section>
      </main>
    )
  }


  /* ==========================================================
     ESTADO: INVITACIÓN INVÁLIDA
     ========================================================== */

  if (!sesionValida) {
    return (
      <main className="auth-page">
        <section className="auth-card">

          <header className="auth-header">
            <div className="auth-logo-wrap">
              <img
                src="/logo-huella.png"
                alt="Fundación Huella"
                className="auth-logo"
              />
            </div>

            <p className="auth-brand">
              HuellApp
            </p>
          </header>


          <div className="auth-state-content">
            <h1 className="auth-state-title">
              Invitación no válida
            </h1>

            <p className="auth-state-text">
              El enlace de invitación no es válido
              o ha expirado.
            </p>
          </div>


          <footer className="auth-footer">
            <Link
              to="/"
              className="auth-link"
            >
              Volver al inicio de sesión
            </Link>
          </footer>

        </section>
      </main>
    )
  }


  /* ==========================================================
     FORMULARIO DE CONTRASEÑA INICIAL
     ========================================================== */

  return (
    <main className="auth-page">
      <section className="auth-card">

        {/* ==================================================
            CABECERA
            ================================================== */}

        <header className="auth-header">
          <div className="auth-logo-wrap">
            <img
              src="/logo-huella.png"
              alt="Fundación Huella"
              className="auth-logo"
            />
          </div>

          <p className="auth-brand">
            HuellApp
          </p>
        </header>


        {/* ==================================================
            CONTENIDO
            ================================================== */}

        <h1 className="auth-title">
          Establecer contraseña
        </h1>

        <p className="auth-subtitle">
          Crea una contraseña para activar el acceso
          a tu cuenta de HuellAPP.
        </p>


        {/* ==================================================
            FORMULARIO
            ================================================== */}

        <form
          className="auth-form"
          onSubmit={handleSubmit}
        >

          {/* --------------------------------------------------
              Contraseña
              -------------------------------------------------- */}

          <div className="auth-field">
            <label
              htmlFor="password"
              className="auth-label"
            >
              Contraseña
            </label>

            <input
              id="password"
              name="password"
              type="password"
              className="auth-input"
              autoComplete="new-password"
              placeholder="Escribe tu contraseña"
              value={password}
              onChange={(event) => {
                setPassword(
                  event.target.value,
                )
              }}
              disabled={loading}
              minLength={8}
              required
            />
          </div>


          {/* --------------------------------------------------
              Confirmación
              -------------------------------------------------- */}

          <div className="auth-field">
            <label
              htmlFor="confirmPassword"
              className="auth-label"
            >
              Confirmar contraseña
            </label>

            <input
              id="confirmPassword"
              name="confirmPassword"
              type="password"
              className="auth-input"
              autoComplete="new-password"
              placeholder="Repite tu contraseña"
              value={confirmPassword}
              onChange={(event) => {
                setConfirmPassword(
                  event.target.value,
                )
              }}
              disabled={loading}
              minLength={8}
              required
            />
          </div>


          {/* ==================================================
              MENSAJE DE ERROR
              ================================================== */}

          {error && (
            <div
              className="
                auth-message
                auth-message--error
              "
              role="alert"
            >
              {error}
            </div>
          )}


          {/* ==================================================
              MENSAJE DE ÉXITO
              ================================================== */}

          {mensaje && (
            <div
              className="
                auth-message
                auth-message--success
              "
              role="status"
              aria-live="polite"
            >
              {mensaje}
            </div>
          )}


          {/* ==================================================
              BOTÓN
              ================================================== */}

          <button
            type="submit"
            className="auth-button"
            disabled={loading}
          >
            {loading
              ? 'Estableciendo contraseña...'
              : 'Establecer contraseña'}
          </button>

        </form>


        {/* ==================================================
            INFORMACIÓN
            ================================================== */}

        <div className="auth-help-box">
          <p>
            La contraseña debe tener al menos
            8 caracteres.
          </p>
        </div>


        {/* ==================================================
            FOOTER
            ================================================== */}

        <footer className="auth-footer">
          <Link
            to="/"
            className="auth-link"
          >
            Volver al inicio de sesión
          </Link>
        </footer>

      </section>
    </main>
  )
}


export default EstablecerPasswordPage