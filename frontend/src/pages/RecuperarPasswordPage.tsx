/**
 * HuellApp
 * Página para solicitar recuperación de contraseña.
 *
 * FLUJO
 * ------------------------------------------------------------
 * 1. El usuario ingresa el correo asociado a su cuenta.
 * 2. Supabase Auth genera el enlace de recuperación.
 * 3. Brevo SMTP entrega el correo.
 * 4. El usuario recibe instrucciones para continuar.
 *
 * SECURITY
 * ------------------------------------------------------------
 * - No se informa si un correo está registrado o no.
 * - Esto evita enumeración de usuarios.
 * - Supabase gestiona los tokens y la seguridad del flujo.
 */

import {
  useState,
} from 'react'

import type { FormEvent } from 'react'

import { Link } from 'react-router-dom'

import { supabase } from '../services/supabase'

import '../styles/auth-pages.css'


function RecuperarPasswordPage() {
  const [email, setEmail] = useState('')

  const [loading, setLoading] = useState(false)

  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')


  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()

    setError('')
    setMensaje('')

    const emailNormalizado =
      email.trim().toLowerCase()

    if (!emailNormalizado) {
      setError(
        'Debes ingresar tu correo electrónico.',
      )

      return
    }

    try {
      setLoading(true)

      const redirectTo =
        `${window.location.origin}/restablecer-password`

      const {
        error: recoverError,
      } = await supabase.auth.resetPasswordForEmail(
        emailNormalizado,
        {
          redirectTo,
        },
      )

      /**
       * Aunque Supabase devuelva un error relacionado
       * con la existencia del usuario, no debemos
       * exponer esa información visualmente.
       */
      if (recoverError) {
        console.error(
          'Error al solicitar recuperación:',
          recoverError,
        )
      }

      setMensaje(
        'Si el correo está registrado en HuellApp, ' +
        'recibirás un mensaje con instrucciones para ' +
        'restablecer tu contraseña.',
      )

      setEmail('')
    } catch (unexpectedError) {
      console.error(
        'Error inesperado al solicitar recuperación:',
        unexpectedError,
      )

      /**
       * Mantenemos una respuesta neutra para no revelar
       * si la cuenta existe.
       */
      setMensaje(
        'Si el correo está registrado en HuellApp, ' +
        'recibirás un mensaje con instrucciones para ' +
        'restablecer tu contraseña.',
      )
    } finally {
      setLoading(false)
    }
  }


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
          Recuperar contraseña
        </h1>

        <p className="auth-subtitle">
          Ingresa el correo asociado a tu cuenta.
          Te enviaremos un enlace para que puedas
          crear una nueva contraseña.
        </p>


        {/* ==================================================
            FORMULARIO
            ================================================== */}

        <form
          className="auth-form"
          onSubmit={handleSubmit}
        >

          <div className="auth-field">

            <label
              htmlFor="email"
              className="auth-label"
            >
              Correo electrónico
            </label>

            <input
              id="email"
              name="email"
              type="email"
              className="auth-input"
              placeholder="nombre@correo.cl"
              autoComplete="email"
              value={email}
              onChange={(event) => {
                setEmail(event.target.value)
              }}
              disabled={loading}
              required
            />

          </div>


          {/* ==================================================
              MENSAJES
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
              ? 'Enviando solicitud...'
              : 'Envíar Solicitud'}
          </button>

        </form>


        {/* ==================================================
            INFORMACIÓN
            ================================================== */}

        <div className="auth-help-box">
          <p>
            Revisa también tu carpeta de spam o correo
            no deseado si el mensaje no aparece en tu
            bandeja de entrada.
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


export default RecuperarPasswordPage