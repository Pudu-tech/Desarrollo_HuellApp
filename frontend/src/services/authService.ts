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
    await supabase.auth.signOut()

    if (response.status === 401 || response.status === 403) {
      throw new Error(
        'Tu usuario no está autorizado para ingresar a HuellAPP.',
      )
    }

    throw new Error(
      'No fue posible validar tu usuario en HuellAPP.',
    )
  }

  return response.json() as Promise<AuthenticatedUser>
}

export async function logout(): Promise<void> {
  await supabase.auth.signOut()
}

export async function getCurrentUser(): Promise<AuthenticatedUser | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession()

  if (!session) {
    return null
  }

  const response = await fetch(`${apiUrl}/auth/me`, {
    headers: {
      Authorization: `Bearer ${session.access_token}`,
    },
  })

  if (!response.ok) {
    await supabase.auth.signOut()
    return null
  }

  return response.json() as Promise<AuthenticatedUser>
}