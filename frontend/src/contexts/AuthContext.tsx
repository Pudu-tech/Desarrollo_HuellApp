import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'

import {
  getCurrentUser,
  login as loginService,
  logout as logoutService,
} from '../services/authService'

import {
  clearSessionTracking,
  getLastActivityAt,
  getSessionStartedAt,
  isSessionExpired,
  isSessionInactive,
  registerSessionActivity,
  startSessionTracking,
} from '../services/sessionPolicy'

import type { AuthenticatedUser } from '../types/auth'

interface AuthContextValue {
  user: AuthenticatedUser | null
  loading: boolean
  login: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(
  undefined,
)

interface AuthProviderProps {
  children: ReactNode
}

const SESSION_CHECK_INTERVAL = 60 * 1000
const ACTIVITY_THROTTLE = 30 * 1000

export function AuthProvider({
  children,
}: AuthProviderProps) {
  const [user, setUser] = useState<AuthenticatedUser | null>(
    null,
  )

  const [loading, setLoading] = useState(true)

  const loggingOutRef = useRef(false)

  const lastActivityUpdateRef = useRef(0)

  /* ============================================================
     CERRAR SESIÓN
     ============================================================ */

  const logout = async () => {
    if (loggingOutRef.current) {
      return
    }

    loggingOutRef.current = true

    try {
      await logoutService()
    } finally {
      clearSessionTracking()
      setUser(null)
      loggingOutRef.current = false
    }
  }

  /* ============================================================
     RESTAURAR SESIÓN
     ============================================================ */

  useEffect(() => {
    const restoreSession = async () => {
      try {
        const currentUser = await getCurrentUser()

        if (!currentUser) {
          clearSessionTracking()
          setUser(null)
          return
        }

        /*
         * Si Supabase conserva una sesión pero HuellApp
         * detecta que superó alguno de sus límites,
         * la sesión debe cerrarse.
         */
        if (
          isSessionInactive() ||
          isSessionExpired()
        ) {
          await logout()
          return
        }

        /*
         * Esto cubre sesiones existentes creadas antes
         * de incorporar la política de sesión.
         *
         * Una vez implementada la política normalmente
         * estas claves siempre deberían existir.
         */
        if (
          getSessionStartedAt() === null ||
          getLastActivityAt() === null
        ) {
          startSessionTracking()
        }

        setUser(currentUser)
      } catch {
        clearSessionTracking()
        setUser(null)
      } finally {
        setLoading(false)
      }
    }

    void restoreSession()
  }, [])

  /* ============================================================
     LOGIN
     ============================================================ */

  const login = async (
    email: string,
    password: string,
  ) => {
    const authenticatedUser = await loginService(
      email,
      password,
    )

    /*
     * Solo un login real reinicia:
     *
     * - duración absoluta de 12 horas
     * - contador de inactividad
     */
    startSessionTracking()

    setUser(authenticatedUser)
  }

  /* ============================================================
     ACTIVIDAD DEL USUARIO
     ============================================================ */

  useEffect(() => {
    if (!user) {
      return
    }

    const handleActivity = () => {
      const now = Date.now()

      /*
       * Evitamos escribir en localStorage con cada
       * movimiento del mouse.
       */
      if (
        now - lastActivityUpdateRef.current <
        ACTIVITY_THROTTLE
      ) {
        return
      }

      /*
       * Antes de registrar nueva actividad verificamos
       * que la sesión todavía sea válida.
       *
       * Esto evita que una interacción después de
       * 30 minutos reviva una sesión vencida.
       */
      if (
        isSessionInactive() ||
        isSessionExpired()
      ) {
        void logout()
        return
      }

      registerSessionActivity()
      lastActivityUpdateRef.current = now
    }

    const activityEvents: Array<keyof WindowEventMap> = [
      'mousedown',
      'keydown',
      'touchstart',
      'scroll',
    ]

    activityEvents.forEach((eventName) => {
      window.addEventListener(
        eventName,
        handleActivity,
        { passive: true },
      )
    })

    return () => {
      activityEvents.forEach((eventName) => {
        window.removeEventListener(
          eventName,
          handleActivity,
        )
      })
    }
  }, [user])

  /* ============================================================
     CONTROL PERIÓDICO
     ============================================================ */

  useEffect(() => {
    if (!user) {
      return
    }

    const validateSession = () => {
      if (
        isSessionInactive() ||
        isSessionExpired()
      ) {
        void logout()
      }
    }

    /*
     * Revisamos inmediatamente por si el navegador
     * estuvo suspendido o la pestaña estuvo congelada.
     */
    validateSession()

    const intervalId = window.setInterval(
      validateSession,
      SESSION_CHECK_INTERVAL,
    )

    return () => {
      window.clearInterval(intervalId)
    }
  }, [user])

  /* ============================================================
     REGRESO A LA PESTAÑA
     ============================================================ */

  useEffect(() => {
    if (!user) {
      return
    }

    const handleVisibilityChange = () => {
      if (document.visibilityState !== 'visible') {
        return
      }

      /*
       * Al volver a HuellApp validamos primero.
       *
       * IMPORTANTE:
       * volver a la pestaña no cuenta automáticamente
       * como actividad.
       */
      if (
        isSessionInactive() ||
        isSessionExpired()
      ) {
        void logout()
      }
    }

    window.addEventListener(
      'focus',
      handleVisibilityChange,
    )

    document.addEventListener(
      'visibilitychange',
      handleVisibilityChange,
    )

    return () => {
      window.removeEventListener(
        'focus',
        handleVisibilityChange,
      )

      document.removeEventListener(
        'visibilitychange',
        handleVisibilityChange,
      )
    }
  }, [user])

  /* ============================================================
     CONTEXTO
     ============================================================ */

  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext)

  if (!context) {
    throw new Error(
      'useAuth debe utilizarse dentro de AuthProvider.',
    )
  }

  return context
}