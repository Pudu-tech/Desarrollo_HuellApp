import { clearReadCache } from './readCache'
import { supabase } from './supabase'

import type { AuthenticatedUser } from '../types/auth'

const apiUrl = import.meta.env.VITE_API_URL

if (!apiUrl) {
  throw new Error('Falta VITE_API_URL.')
}

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

export async function logout(): Promise<void> {
  clearReadCache()
  await supabase.auth.signOut()
}

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
