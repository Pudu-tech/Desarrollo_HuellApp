/**
 * HuellApp · Autenticación y validación de sesión.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Autenticar con Supabase Auth y consultar el perfil autorizado en /auth/me.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Renueva una sesión rechazada con 401 y distingue fallos temporales de falta de acceso.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Utiliza la sesión del usuario; los permisos se validan en FastAPI.
 * Las credenciales privilegiadas de Supabase permanecen en el backend.
 */
import { clearReadCache } from './readCache'
import { supabase } from './supabase'

import type { AuthenticatedUser } from '../types/auth'

const apiUrl = import.meta.env.VITE_API_URL

if (!apiUrl) {
  throw new Error('Falta VITE_API_URL.')
}

/** Autentica en Supabase Auth y obtiene el perfil autorizado; limpia las lecturas de la sesión anterior. */
export async function login(
  email: string,
  password: string,
): Promise<AuthenticatedUser> {
  clearReadCache()
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  })

  if (error || !data.session) {
    throw new Error('Correo o contraseña incorrectos.')
  }

  const response = await fetch(`${apiUrl}/auth/me`, {
    headers: {
      Authorization: `Bearer ${data.session.access_token}`,
    },
  })

  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      await supabase.auth.signOut()
      throw new Error(
        'Tu usuario no está autorizado para ingresar a HuellApp.',
      )
    }

    throw new Error(
      'No fue posible validar tu usuario en HuellApp.',
    )
  }

  return response.json() as Promise<AuthenticatedUser>
}

/** Invalida la caché de lecturas y solicita el cierre de sesión en Supabase Auth. */
export async function logout(): Promise<void> {
  clearReadCache()
  await supabase.auth.signOut()
}

/** Valida el perfil actual y renueva una vez ante HTTP 401; distingue indisponibilidad de falta de acceso. */
export async function getCurrentUser(): Promise<AuthenticatedUser | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession()

  if (!session) {
    return null
  }

  let response = await fetch(`${apiUrl}/auth/me`, {
    headers: {
      Authorization: `Bearer ${session.access_token}`,
    },
  })

  if (response.status === 401) {
    const refreshed = await supabase.auth.refreshSession()
    if (refreshed.error || !refreshed.data.session) {
      throw new Error('No se pudo renovar la sesión. Reintenta o vuelve a iniciar sesión.')
    }
    response = await fetch(`${apiUrl}/auth/me`, {
      headers: { Authorization: `Bearer ${refreshed.data.session.access_token}` },
    })
  }

  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      await supabase.auth.signOut()
      return null
    }
    throw new Error('El servicio no pudo validar tu sesión temporalmente. Reintenta.')
  }

  return response.json() as Promise<AuthenticatedUser>
}
