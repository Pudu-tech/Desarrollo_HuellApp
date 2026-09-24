/**
 * HuellApp
 * Página para restablecer la contraseña.
 *
 * FLUJO
 * ------------------------------------------------------------
 * 1. El usuario solicita recuperación.
 * 2. Supabase envía el correo mediante Brevo.
 * 3. El usuario abre el enlace recibido.
 * 4. Supabase crea una sesión temporal de recuperación.
 * 5. El usuario establece una nueva contraseña.
 * 6. Cerramos la sesión temporal.
 * 7. Redirigimos al Login.
 * 8. El usuario debe iniciar sesión manualmente.
 *
 * SECURITY
 * ------------------------------------------------------------
 * - No procesamos manualmente access_token ni refresh_token.
 * - Supabase Auth administra la sesión de recuperación.
 * - La contraseña se actualiza mediante updateUser().
 * - Después del cambio se cierra la sesión local.
 * - No se inicia sesión automáticamente después del cambio.
 */

import {
  useEffect,
  useState,
} from 'react'

import type { FormEvent } from 'react'

import { Link } from 'react-router-dom'

import { supabase } from '../services/supabase'

import '../styles/auth-pages.css'


function RestablecerPasswordPage() {
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
     VALIDACIÓN DE SESIÓN DE RECUPERACIÓN
     ========================================================== */

  useEffect(() => {
    let mounted = true


    /**
     * Verificamos si Supabase pudo crear correctamente
     * la sesión temporal proveniente del enlace
     * de recuperación.
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
          'Error al validar sesión de recuperación:',
          sessionError,
        )

        setSesionValida(false)
        setValidandoSesion(false)

        return
      }


      if (data.session) {
        setSesionValida(true)
      } else {
        setSesionValida(false)
      }


      setValidandoSesion(false)
    }


    validarSesion()


    /**
     * Supabase puede disparar PASSWORD_RECOVERY
     * cuando procesa correctamente el enlace recibido
     * por correo.
     *
     * Dependiendo del flujo de Auth también puede
     * producirse SIGNED_IN durante el establecimiento
     * de la sesión temporal.
     */
    const {
      data: authListener,
    } = supabase.auth.onAuthStateChange(
      (event) => {
        if (
          event === 'PASSWORD_RECOVERY' ||
          event === 'SIGNED_IN'
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
     CAMBIO DE CONTRASEÑA
     ========================================================== */

  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

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
         Actualización de contraseña
         -------------------------------------------------------- */

      const {
        error: updateError,
      } = await supabase.auth.updateUser({
        password,
      })


      if (updateError) {
        console.error(
          'Error al actualizar contraseña:',
          updateError,
        )


        const mensajeError =
          updateError.message?.toLowerCase() ?? ''


        /* ------------------------------------------------------
           Nueva contraseña igual a la anterior
           ------------------------------------------------------ */

        if (
          mensajeError.includes('same password') ||
          mensajeError.includes(
            'different from the old password',
          ) ||
          mensajeError.includes(
            'new password should be different',
          )
        ) {
          setError(
            'La nueva contraseña debe ser diferente ' +
            'a tu contraseña anterior.',
          )

          return
        }


        /* ------------------------------------------------------
           Contraseña considerada débil
           ------------------------------------------------------ */

        if (
          mensajeError.includes('password') &&
          mensajeError.includes('weak')
        ) {
          setError(
            'La contraseña no cumple con los ' +
            'requisitos de seguridad.',
          )

          return
        }


        /* ------------------------------------------------------
           Error genérico
           ------------------------------------------------------ */

        setError(
          'No fue posible actualizar la contraseña. ' +
          'Solicita un nuevo enlace de recuperación.',
        )

        return
      }


      /* --------------------------------------------------------
         Cambio exitoso
         -------------------------------------------------------- */

      setMensaje(
        'Tu contraseña fue actualizada correctamente. ' +
        'Por seguridad, inicia sesión nuevamente con ' +
        'tu nueva contraseña.',
      )


      /* --------------------------------------------------------
         Cierre de la sesión temporal de recuperación
         --------------------------------------------------------
         IMPORTANTE:
         Usamos scope local para cerrar solamente la sesión
         de este navegador.

         No cerramos las sesiones que el usuario pudiera tener
         abiertas en otros dispositivos.
         -------------------------------------------------------- */

      const {
        error: signOutError,
      } = await supabase.auth.signOut({
        scope: 'local',
      })


      if (signOutError) {
        console.error(
          'Error al cerrar sesión de recuperación:',
          signOutError,
        )
      }


      /* --------------------------------------------------------
         Redirección limpia al Login
         --------------------------------------------------------
         Usamos window.location.replace() en lugar de navigate()
         para forzar una carga nueva de la aplicación.

         Esto evita reutilizar el estado de autenticación
         mantenido en memoria por AuthContext.
         -------------------------------------------------------- */

      setTimeout(() => {
        window.location.replace('/')
      }, 1800)

    } catch (unexpectedError) {
      console.error(
        'Error inesperado al restablecer contraseña:',
        unexpectedError,
      )

      setError(
        'Ocurrió un error al actualizar la contraseña.',
      )

    } finally {
      setLoading(false)
    }
  }


  /* ==========================================================
     ESTADO: VALIDANDO ENLACE
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
              Validando enlace
            </h1>

            <p className="auth-state-text">
              Estamos comprobando tu enlace de
              recuperación.
            </p>

          </div>

        </section>

      </main>
    )
  }


  /* ==========================================================
     ESTADO: ENLACE INVÁLIDO
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
              Enlace no válido
            </h1>

            <p className="auth-state-text">
              El enlace de recuperación no es válido
              o ha expirado.
            </p>

          </div>


          <footer className="auth-footer">

            <Link
              to="/recuperar-password"
              className="auth-link"
            >
              Solicitar un nuevo enlace
            </Link>

          </footer>

        </section>

      </main>
    )
  }


  /* ==========================================================
     FORMULARIO DE NUEVA CONTRASEÑA
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
          Restablecer contraseña
        </h1>

        <p className="auth-subtitle">
          Ingresa una nueva contraseña para recuperar
          el acceso a tu cuenta.
        </p>


        {/* ==================================================
            FORMULARIO
            ================================================== */}

        <form
          className="auth-form"
          onSubmit={handleSubmit}
        >

          {/* --------------------------------------------------
              Nueva contraseña
              -------------------------------------------------- */}

          <div className="auth-field">

            <label
              htmlFor="password"
              className="auth-label"
            >
              Nueva contraseña
            </label>

            <input
              id="password"
              name="password"
              type="password"
              className="auth-input"
              autoComplete="new-password"
              placeholder="Escribe tu nueva contraseña"
              value={password}
              onChange={(event) => {
                setPassword(event.target.value)
              }}
              disabled={loading}
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
              placeholder="Repite tu nueva contraseña"
              value={confirmPassword}
              onChange={(event) => {
                setConfirmPassword(
                  event.target.value,
                )
              }}
              disabled={loading}
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
              ? 'Actualizando contraseña...'
              : 'Actualizar contraseña'}
          </button>

        </form>


        {/* ==================================================
            INFORMACIÓN
            ================================================== */}

        <div className="auth-help-box">

          <p>
            La nueva contraseña debe tener al menos
            8 caracteres y ser diferente a tu
            contraseña anterior.
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


export default RestablecerPasswordPage