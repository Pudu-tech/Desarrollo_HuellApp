/**
 * HuellApp
 * Tipos utilizados por el módulo de usuarios.
 */

export type UserRoleCode =
  | 'SUPERADMIN'
  | 'DIRECTIVA'
  | 'COORDINADOR'
  | 'MONITOR'


export interface UserRoleSummary {
  codigo: UserRoleCode
  nombre: string
}


export interface UserListItem {
  id: string
  rut: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string
  email: string
  telefono: string | null
  activo: boolean
  roles: UserRoleSummary
}


/**
 * Payload utilizado al crear un usuario.
 *
 * La contraseña no forma parte del payload:
 * el usuario la establece mediante la invitación.
 */
export interface UserCreatePayload {
  rut: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string
  email: string
  telefono: string | null
  role_code: UserRoleCode
}


/**
 * Datos básicos permitidos por el endpoint:
 *
 * PATCH /users/{user_id}
 *
 * El correo, rol, contraseña y estado se administran
 * mediante otros flujos.
 */
export interface UserUpdatePayload {
  rut?: string
  nombres?: string
  apellido_paterno?: string
  apellido_materno?: string
  telefono?: string | null
}


/**
 * Payload utilizado para el cambio controlado de correo.
 *
 * PATCH /users/{user_id}/email
 */
export interface UserEmailUpdatePayload {
  email: string
}


/**
 * Payload utilizado para cambio de rol.
 */
export interface UserRoleUpdatePayload {
  role_code: UserRoleCode
}