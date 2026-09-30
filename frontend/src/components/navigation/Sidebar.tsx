/**
 * HuellAPP
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

import {
  ADMIN_NAVIGATION_ITEMS,
  MONITOR_NAVIGATION_ITEMS,
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
  /**
   * El MONITOR utiliza una navegación propia.
   *
   * Los demás roles utilizan la navegación
   * administrativa.
   */
  const navigationItems =
    role === 'MONITOR'
      ? MONITOR_NAVIGATION_ITEMS
      : ADMIN_NAVIGATION_ITEMS


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
          HuellAPP
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