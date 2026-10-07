/**
 * HuellApp · Contratos de los contactos asociados a colegios.
 * La API administra permisos, normalización del RUT y auditoría.
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
