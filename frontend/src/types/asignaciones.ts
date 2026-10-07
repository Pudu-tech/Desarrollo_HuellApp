/** HuellApp · Contratos existentes de Asignaciones y proyecciones de sus catálogos. */
export interface OpcionNombre { id: string; nombre: string }
export interface OpcionCodigo extends OpcionNombre { codigo: string }
export interface AsignacionItem {
  id: string
  tipo_actividad_id: string
  colegio_id: string | null
  curso_colegio_id: string | null
  sala_id: string | null
  ramo_id: string | null
  espacio_reflexion_id: string | null
  espacio_encuentro_id: string | null
  fecha: string
  hora_inicio: string
  hora_fin: string
  lugar: string | null
  observacion: string | null
  estado_id: string
  activo: boolean
  created_at: string
  updated_at: string
}
export interface ParticipantePayload { usuario_id: string; tipo_participacion_id: string }
export interface AsignacionPayload {
  tipo_actividad_id: string
  colegio_id: string | null
  curso_colegio_id: string | null
  sala_id: string | null
  ramo_id: string | null
  espacio_reflexion_id: string | null
  espacio_encuentro_id: string | null
  fecha: string
  hora_inicio: string
  hora_fin: string
  lugar: string | null
  observacion: string | null
  participantes: ParticipantePayload[]
  contactos: Array<{ contacto_colegio_id: string }>
}
export interface AsignacionDetail extends AsignacionItem {
  participantes: Array<ParticipantePayload & { id: string; estado_participacion_id: string; activo: boolean }>
  contactos: Array<{ id: string; contacto_colegio_id: string }>
}
export interface CatalogosAsignacion {
  tipos_actividad: OpcionCodigo[]
  estados: OpcionCodigo[]
  colegios: OpcionNombre[]
}
export interface ParticipanteOpcion {
  id: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string | null
  role_code: string
}
export interface OpcionesCreacion {
  tipos_actividad: OpcionCodigo[]
  colegios: OpcionNombre[]
  participantes: ParticipanteOpcion[]
  tipos_participacion: OpcionCodigo[]
  ramos: Array<OpcionNombre & { nivel_curso_id: string | null; nivel_ids: string[] }>
}
export interface OpcionesColegio {
  cursos: Array<{ id: string; nombre_mostrado: string; nivel_curso_id: string; anio: number }>
  salas: OpcionNombre[]
  contactos: Array<OpcionNombre & { apellido_paterno: string | null; apellido_materno: string | null; cargo: string | null }>
}
export interface OpcionesEspacios { reflexion: OpcionNombre[]; encuentro: OpcionNombre[] }
