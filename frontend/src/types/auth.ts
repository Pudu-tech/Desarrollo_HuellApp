/**
 * HuellApp · Contratos de identidad autenticada.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Definir las estructuras TypeScript utilizadas para identidad autenticada.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Tipos compartidos entre servicios, componentes y páginas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Estos tipos no validan datos en ejecución ni conceden permisos.
 * La API es responsable de validar los datos y autorizar las operaciones.
 */
export interface AuthenticatedUser {
  id: string
  email: string
  nombres: string
  apellido_paterno: string
  role_code: string
}