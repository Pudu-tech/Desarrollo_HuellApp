/**
 * HuellApp · Contratos de contactos escolares.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Definir las estructuras TypeScript utilizadas para contactos escolares.
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
export interface ContactoColegio {
  id: string
  colegio_id: string
  nombre: string
  apellido_paterno: string | null
  apellido_materno: string | null
  rut: string | null
  email: string
  telefono: string
  cargo: string | null
  activo: boolean
}

/** Campos editables; jamás se envían los datos internos de auditoría. */
export type ContactoPayload = Pick<ContactoColegio,
  'nombre' | 'apellido_paterno' | 'apellido_materno' | 'rut' | 'email' | 'telefono' | 'cargo'>
