/**
 * HuellApp · Filtros del listado de instancias.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Preparar opciones de colegios y aplicar filtros sobre las actividades cargadas.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Conserva el contexto histórico de las actividades y excluye colegios eliminados del selector.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
export function ordenarPorFecha<T extends { fecha: string; hora_inicio: string }>(items: readonly T[], direction: 'asc' | 'desc'): T[] {
  // Acepta entradas readonly para probar la inmutabilidad; espera fechas ISO y horas HH:mm.
  const sign = direction === 'asc' ? 1 : -1
  return [...items].sort((a, b) => sign * (a.fecha.localeCompare(b.fecha) || a.hora_inicio.localeCompare(b.hora_inicio)))
}

/** Prepara el selector con colegios disponibles sin borrar las referencias de actividades históricas. */
export function colegiosDisponibles<T extends { activo?: boolean; deleted_at?: string | null }>(items: readonly T[]): T[] {
  // La suite comprueba el filtro con datos locales, incluidos registros históricos, sin consultar Supabase.
  return items.filter((item) => item.activo !== false && !item.deleted_at)
}
