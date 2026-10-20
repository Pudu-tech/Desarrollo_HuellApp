/** Copia el listado para ordenar sin modificar los datos originales. */
export function ordenarPorFecha<T extends { fecha: string; hora_inicio: string }>(items: T[], direction: 'asc' | 'desc'): T[] {
  const sign = direction === 'asc' ? 1 : -1
  return [...items].sort((a, b) => sign * (a.fecha.localeCompare(b.fecha) || a.hora_inicio.localeCompare(b.hora_inicio)))
}

export function colegiosDisponibles<T extends { activo?: boolean; deleted_at?: string | null }>(items: T[]): T[] {
  return items.filter((item) => item.activo !== false && !item.deleted_at)
}
