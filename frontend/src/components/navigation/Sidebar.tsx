/**
 * HuellAPP
 * Sidebar principal para roles administrativos.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Mostrar navegación permitida por rol.
 * - Mostrar información básica del usuario autenticado.
 * - Exponer la acción de cierre de sesión.
 *
 * La lógica de autenticación permanece en AuthContext.
 */

import SidebarItem from './SidebarItem'

import {
  ADMIN_NAVIGATION_ITEMS,
} from '../../config/navigation'

import type {
  AppRole,
} from '../../types/navigation'

interface SidebarProps {
  email: string
  role: AppRole
  onLogout: () => Promise<void>
}

function Sidebar({
  email,
  role,
  onLogout,
}: SidebarProps) {
  const visibleNavigationItems =
    ADMIN_NAVIGATION_ITEMS.filter(
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
            {email}
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