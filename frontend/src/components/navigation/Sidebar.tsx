/**
 * HuellApp
 * Sidebar principal de la aplicación.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Mostrar navegación permitida por rol.
 * - Adaptar la navegación para roles administrativos
 *   y MONITOR.
 * - Mostrar información básica del usuario autenticado.
 * - Exponer la acción de cierre de sesión.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La visibilidad del menú no constituye autorización.
 * RoleRoute y FastAPI continúan siendo responsables
 * del acceso real a cada recurso.
 */

import SidebarItem from './SidebarItem'
import { useEffect, useState } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { useVisibleRefresh } from '../../hooks/useVisibleRefresh'
import { listMisParticipaciones } from '../../services/participacionesService'

import {
  navigationForRole,
} from '../../config/navigation'

import type {
  AppRole,
} from '../../types/navigation'


interface SidebarProps {
  displayName: string
  role: AppRole
  onLogout: () => Promise<void>
}


function Sidebar({
  displayName,
  role,
  onLogout,
}: SidebarProps) {
  const { user } = useAuth()
  const receivesAssignments = ['MONITOR', 'DIRECTIVA', 'COORDINADOR'].includes(role)
  const [pending, setPending] = useState<{ user: string; count: number; attendance: number } | null>(null)
  const userId = user?.id ?? ''
  useEffect(() => {
    if (!receivesAssignments || !userId) return
    let active = true
    void listMisParticipaciones().then((rows) => {
      if (active) setPending({ user: userId, count: rows.filter((item) => item.admite_respuesta).length, attendance: rows.filter((item) => item.admite_asistencia).length })
    }).catch(() => { /* No interrumpe la navegación si falla el contador. */ })
    return () => { active = false }
  }, [receivesAssignments, userId])
  useVisibleRefresh(async (isActive) => {
    try {
      const rows = await listMisParticipaciones()
      if (isActive()) setPending({ user: userId, count: rows.filter((item) => item.admite_respuesta).length, attendance: rows.filter((item) => item.admite_asistencia).length })
    } catch { /* Conserva el último contador confirmado y reintenta. */ }
  }, receivesAssignments && !!userId)
  /**
   * El MONITOR utiliza una navegación propia.
   *
   * Los demás roles utilizan la navegación
   * administrativa.
   */
  const navigationItems = navigationForRole(role)


  /**
   * Segunda capa de filtrado según rol.
   */
  const visibleNavigationItems =
    navigationItems.filter(
      (item) =>
        item.allowedRoles.includes(role),
    )


  return (
    <aside className="sidebar">
      <div className="sidebar__header">
        <h1 className="sidebar__title">
          HuellApp
        </h1>

        <span className="sidebar__subtitle">
          Fundación Huella
        </span>
      </div>


      <nav
        className="sidebar__navigation"
        aria-label="Navegación principal"
      >
        <ul className="sidebar__list">
          {visibleNavigationItems.map(
            (item) => (
              <SidebarItem
                key={item.path}
                label={item.label}
                path={item.path}
                count={pending?.user === userId ? ['/app/mis-asignaciones', '/app/monitor/asignaciones'].includes(item.path) ? pending.count : ['/app/asistencia', '/app/monitor/asistencia'].includes(item.path) ? pending.attendance : 0 : 0}
                countLabel={item.path.endsWith('/asistencia') ? 'asistencias propias pendientes dentro del plazo' : 'asignaciones pendientes de respuesta'}
              />
            ),
          )}
        </ul>
      </nav>


      <div className="sidebar__footer">
        <div className="sidebar__user">
          <span className="sidebar__user-email">
            {displayName}
          </span>

          <span className="sidebar__user-role">
            {role}
          </span>
        </div>

        <button
          type="button"
          className="sidebar__logout"
          onClick={() => {
            void onLogout()
          }}
        >
          Cerrar sesión
        </button>
      </div>
    </aside>
  )
}


export default Sidebar
