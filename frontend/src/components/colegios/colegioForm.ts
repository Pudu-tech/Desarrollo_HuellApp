/**
 * HuellApp · Estado y normalización de formularios de colegios.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Nombre, dirección, región y comuna son obligatorios en el backend.
 * - Los campos opcionales vacíos se envían como null.
 * - El estado activo y los metadatos de auditoría nunca se envían desde aquí.
 */

import type { ColegioCreatePayload, ColegioListItem, ComunaItem } from '../../types/colegios'

/** Campos editables compartidos por POST y PATCH. */
export type ColegioFormValues = ColegioCreatePayload

/** Estado inicial para registrar un establecimiento. */
export const EMPTY_COLEGIO: ColegioFormValues = {
  rbd: null,
  nombre: '',
  descripcion: null,
  tipo_dependencia_id: null,
  direccion: '',
  numero: null,
  complemento: null,
  comuna_id: '',
  region_id: '',
  codigo_postal: null,
  telefono: null,
  email: null,
  sitio_web: null,
  nombre_contacto: null,
  telefono_contacto: null,
  email_contacto: null,
}

/** Excluye los campos de lectura y administración al abrir una edición. */
export function colegioToForm(colegio: ColegioListItem): ColegioFormValues {
  return {
    rbd: colegio.rbd,
    nombre: colegio.nombre,
    descripcion: colegio.descripcion,
    tipo_dependencia_id: colegio.tipo_dependencia_id,
    direccion: colegio.direccion,
    numero: colegio.numero,
    complemento: colegio.complemento,
    comuna_id: colegio.comuna_id,
    region_id: colegio.region_id,
    codigo_postal: colegio.codigo_postal,
    telefono: colegio.telefono,
    email: colegio.email,
    sitio_web: colegio.sitio_web,
    nombre_contacto: colegio.nombre_contacto,
    telefono_contacto: colegio.telefono_contacto,
    email_contacto: colegio.email_contacto,
  }
}

const optionalFields = [
  'rbd', 'descripcion', 'tipo_dependencia_id', 'numero', 'complemento',
  'codigo_postal', 'telefono', 'email', 'sitio_web', 'nombre_contacto',
  'telefono_contacto', 'email_contacto',
] as const satisfies ReadonlyArray<keyof ColegioFormValues>

/** Normaliza textos antes de enviar al servidor; el backend vuelve a validarlos. */
export function normalizeColegio(values: ColegioFormValues): ColegioFormValues {
  const result = { ...values }
  result.nombre = result.nombre.trim()
  result.direccion = result.direccion.trim()
  for (const field of optionalFields) {
    const value = result[field]
    if (typeof value === 'string') {
      // Estos campos admiten null; se evita persistir cadenas vacías.
      result[field] = value.trim() || null
    }
  }
  return result
}

/** Verifica los campos obligatorios y la pertenencia de la comuna a la región. */
export function validateColegio(values: ColegioFormValues, comunas: ComunaItem[]): string | null {
  if (!values.nombre.trim() || !values.direccion.trim() || !values.region_id || !values.comuna_id) {
    return 'Completa nombre, dirección, región y comuna.'
  }
  if (!comunas.some((comuna) => comuna.id === values.comuna_id && comuna.region_id === values.region_id)) {
    return 'Selecciona una comuna válida para la región indicada.'
  }
  return null
}
