/**
 * HuellApp
 * Elemento individual de navegación del sidebar.
 */

import { NavLink } from 'react-router-dom'

interface SidebarItemProps {
  label: string
  path: string
  count?: number
  countLabel?: string
}

function SidebarItem({
  label,
  path,
  count = 0,
  countLabel = 'asignaciones pendientes de respuesta',
}: SidebarItemProps) {
  return (
    <li className="sidebar__item">
      <NavLink
        to={path}
        className={({ isActive }) =>
          isActive
            ? 'sidebar__link sidebar__link--active'
            : 'sidebar__link'
        }
      >
        {label}
        {count > 0 && <span className="sidebar__badge" title={`${count} ${countLabel}`} aria-label={`${count} ${countLabel}`}>{count > 99 ? '99+' : count}</span>}
      </NavLink>
    </li>
  )
}

export default SidebarItem
