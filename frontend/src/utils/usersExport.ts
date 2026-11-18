import type { UserListItem } from '../types/users'
import { sortList, type SortDirection } from './listSort'
import type { ExportTable } from './queryExport'

export const userFullName = (user: UserListItem) => [user.nombres, user.apellido_paterno, user.apellido_materno].filter(Boolean).join(' ').trim()

export function usersExportTable(items: UserListItem[], generatedAt: string, direction: SortDirection): ExportTable {
  return {
    title: 'Usuarios', generatedAt, order: `Nombre ${direction === 'asc' ? 'ascendente' : 'descendente'}`,
    columns: ['RUT', 'Nombre', 'Correo', 'Teléfono', 'Rol', 'Estado'],
    rows: sortList(items, userFullName, direction).map(user => [user.rut, userFullName(user), user.email, user.telefono ?? '-', user.roles.nombre, user.activo ? 'Activo' : 'Inactivo']),
  }
}
