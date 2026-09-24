/**
 * HuellApp
 * Política de duración de sesión.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Cierre por inactividad: 30 minutos.
 * - Duración máxima absoluta: 12 horas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La sesión de Supabase puede renovar automáticamente su JWT.
 * Por ello, HuellApp mantiene adicionalmente sus propios
 * tiempos de sesión para aplicar estas reglas de seguridad.
 */


/* ============================================================
   CONFIGURACIÓN
   ============================================================ */

export const SESSION_INACTIVITY_LIMIT =
  30 * 60 * 1000

export const SESSION_ABSOLUTE_LIMIT =
  12 * 60 * 60 * 1000

/* ============================================================
   CLAVES DE ALMACENAMIENTO
   ============================================================ */

const SESSION_STARTED_AT_KEY =
  'huellapp_session_started_at'

const LAST_ACTIVITY_AT_KEY =
  'huellapp_last_activity_at'


/* ============================================================
   INICIAR CONTROL DE SESIÓN
   ============================================================ */

/**
 * Registra el inicio de una nueva sesión.
 *
 * Debe ejecutarse solamente cuando el usuario
 * inicia sesión correctamente.
 */
export function startSessionTracking(): void {
  const now = Date.now()

  localStorage.setItem(
    SESSION_STARTED_AT_KEY,
    now.toString(),
  )

  localStorage.setItem(
    LAST_ACTIVITY_AT_KEY,
    now.toString(),
  )
}


/* ============================================================
   REGISTRAR ACTIVIDAD
   ============================================================ */

/**
 * Actualiza únicamente la última actividad.
 *
 * NO modifica la fecha inicial de sesión,
 * porque el límite absoluto de 12 horas
 * nunca debe reiniciarse.
 */
export function registerSessionActivity(): void {
  localStorage.setItem(
    LAST_ACTIVITY_AT_KEY,
    Date.now().toString(),
  )
}


/* ============================================================
   OBTENER INICIO DE SESIÓN
   ============================================================ */

export function getSessionStartedAt():
  number | null {
  const value =
    localStorage.getItem(
      SESSION_STARTED_AT_KEY,
    )

  if (!value) {
    return null
  }

  const timestamp = Number(value)

  return Number.isFinite(timestamp)
    ? timestamp
    : null
}


/* ============================================================
   OBTENER ÚLTIMA ACTIVIDAD
   ============================================================ */

export function getLastActivityAt():
  number | null {
  const value =
    localStorage.getItem(
      LAST_ACTIVITY_AT_KEY,
    )

  if (!value) {
    return null
  }

  const timestamp = Number(value)

  return Number.isFinite(timestamp)
    ? timestamp
    : null
}


/* ============================================================
   VALIDAR INACTIVIDAD
   ============================================================ */

export function isSessionInactive(): boolean {
  const lastActivity =
    getLastActivityAt()

  if (!lastActivity) {
    return false
  }

  return (
    Date.now() - lastActivity >=
    SESSION_INACTIVITY_LIMIT
  )
}


/* ============================================================
   VALIDAR DURACIÓN ABSOLUTA
   ============================================================ */

export function isSessionExpired(): boolean {
  const startedAt =
    getSessionStartedAt()

  if (!startedAt) {
    return false
  }

  return (
    Date.now() - startedAt >=
    SESSION_ABSOLUTE_LIMIT
  )
}


/* ============================================================
   LIMPIAR DATOS
   ============================================================ */

/**
 * Elimina los timestamps locales asociados
 * a la política de sesión.
 *
 * Debe ejecutarse al cerrar sesión.
 */
export function clearSessionTracking(): void {
  localStorage.removeItem(
    SESSION_STARTED_AT_KEY,
  )

  localStorage.removeItem(
    LAST_ACTIVITY_AT_KEY,
  )
}