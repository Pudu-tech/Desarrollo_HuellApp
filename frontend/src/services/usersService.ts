/**
 * HuellAPP
 * Servicio del mantenedor de usuarios.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Obtener el token autenticado.
 * - Consumir los endpoints administrativos de usuarios.
 * - Propagar los mensajes de error entregados por FastAPI.
 *
 * SECURITY
 * ------------------------------------------------------------
 * - No contiene credenciales administrativas.
 * - El access token proviene de Supabase Auth.
 * - La autorización definitiva permanece en FastAPI.
 */

import { supabase } from './supabase'

import type {
  UserCreatePayload,
  UserListItem,
  UserRoleUpdatePayload,
  UserUpdatePayload,
} from '../types/users'


// ============================================================
// CONFIGURACIÓN
// ============================================================

const rawApiUrl = import.meta.env.VITE_API_URL

if (!rawApiUrl) {
  throw new Error(
    'Falta la variable de entorno VITE_API_URL.',
  )
}

const apiUrl = rawApiUrl.replace(/\/+$/, '')


// ============================================================
// TIPOS INTERNOS DE ERROR
// ============================================================

interface FastApiValidationError {
  loc?: Array<string | number>
  msg?: string
  type?: string
}


interface FastApiErrorResponse {
  detail?:
    | string
    | FastApiValidationError[]
}


// ============================================================
// AUTENTICACIÓN
// ============================================================

async function getAccessToken(): Promise<string> {
  const {
    data: { session },
    error,
  } = await supabase.auth.getSession()

  if (error) {
    throw new Error(
      'No fue posible validar la sesión actual.',
    )
  }

  if (!session?.access_token) {
    throw new Error(
      'La sesión ha finalizado. '
      + 'Inicia sesión nuevamente.',
    )
  }

  return session.access_token
}


// ============================================================
// ERRORES
// ============================================================

async function getResponseErrorMessage(
  response: Response,
): Promise<string> {
  try {
    const body =
      (await response.json()) as FastApiErrorResponse

    if (
      typeof body.detail === 'string'
      && body.detail.trim()
    ) {
      return body.detail
    }

    if (
      Array.isArray(body.detail)
      && body.detail.length > 0
    ) {
      const messages = body.detail
        .map((item) => item.msg)
        .filter(
          (message): message is string =>
            typeof message === 'string'
            && message.trim().length > 0,
        )

      if (messages.length > 0) {
        return messages.join(' ')
      }
    }
  } catch {
    // Se utiliza mensaje por código HTTP.
  }

  switch (response.status) {
    case 400:
      return 'Los datos enviados no son válidos.'

    case 401:
      return (
        'La sesión ha finalizado. '
        + 'Inicia sesión nuevamente.'
      )

    case 403:
      return (
        'No tienes permisos para realizar '
        + 'esta operación.'
      )

    case 404:
      return 'El usuario no existe.'

    case 409:
      return (
        'Existe un conflicto con los datos '
        + 'del usuario.'
      )

    case 422:
      return (
        'Los datos ingresados no cumplen '
        + 'con el formato esperado.'
      )

    default:
      return (
        'Ocurrió un error inesperado. '
        + 'Intenta nuevamente.'
      )
  }
}


/**
 * Ejecuta una solicitud autenticada que retorna JSON.
 */
async function requestUserJson(
  path: string,
  options: RequestInit,
): Promise<UserListItem> {
  const accessToken =
    await getAccessToken()

  const response = await fetch(
    `${apiUrl}${path}`,
    {
      ...options,
      headers: {
        Authorization:
          `Bearer ${accessToken}`,
        Accept: 'application/json',
        ...(options.body
          ? {
              'Content-Type':
                'application/json',
            }
          : {}),
        ...options.headers,
      },
    },
  )

  if (!response.ok) {
    const message =
      await getResponseErrorMessage(response)

    throw new Error(message)
  }

  const data =
    (await response.json()) as UserListItem

  return data
}


// ============================================================
// LISTADO
// ============================================================

export async function getUsers():
Promise<UserListItem[]> {
  const accessToken =
    await getAccessToken()

  const response = await fetch(
    `${apiUrl}/users`,
    {
      method: 'GET',
      headers: {
        Authorization:
          `Bearer ${accessToken}`,
        Accept: 'application/json',
      },
    },
  )

  if (!response.ok) {
    const message =
      await getResponseErrorMessage(response)

    throw new Error(message)
  }

  const data =
    (await response.json()) as UserListItem[]

  return data
}


// ============================================================
// CREACIÓN
// ============================================================

export async function createUser(
  payload: UserCreatePayload,
): Promise<UserListItem> {
  return requestUserJson(
    '/users',
    {
      method: 'POST',
      body: JSON.stringify(payload),
    },
  )
}


// ============================================================
// EDICIÓN DE DATOS BÁSICOS
// ============================================================

export async function updateUser(
  userId: string,
  payload: UserUpdatePayload,
): Promise<UserListItem> {
  return requestUserJson(
    `/users/${userId}`,
    {
      method: 'PATCH',
      body: JSON.stringify(payload),
    },
  )
}


// ============================================================
// CAMBIO DE ROL
// ============================================================

export async function updateUserRole(
  userId: string,
  payload: UserRoleUpdatePayload,
): Promise<UserListItem> {
  return requestUserJson(
    `/users/${userId}/role`,
    {
      method: 'PATCH',
      body: JSON.stringify(payload),
    },
  )
}


// ============================================================
// ACTIVACIÓN
// ============================================================

export async function activateUser(
  userId: string,
): Promise<UserListItem> {
  return requestUserJson(
    `/users/${userId}/activate`,
    {
      method: 'PATCH',
    },
  )
}


// ============================================================
// DESACTIVACIÓN
// ============================================================

export async function deactivateUser(
  userId: string,
): Promise<UserListItem> {
  return requestUserJson(
    `/users/${userId}/deactivate`,
    {
      method: 'PATCH',
    },
  )
}


// ============================================================
// ELIMINACIÓN
// ============================================================

export async function deleteUser(
  userId: string,
): Promise<void> {
  const accessToken =
    await getAccessToken()

  const response = await fetch(
    `${apiUrl}/users/${userId}`,
    {
      method: 'DELETE',
      headers: {
        Authorization:
          `Bearer ${accessToken}`,
        Accept: 'application/json',
      },
    },
  )

  if (!response.ok) {
    const message =
      await getResponseErrorMessage(response)

    throw new Error(message)
  }
}