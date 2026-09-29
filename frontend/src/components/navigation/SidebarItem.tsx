/**
 * HuellAPP
 * Elemento individual de navegación del sidebar.
 */

import { NavLink } from 'react-router-dom'

interface SidebarItemProps {
  label: string
  path: string
}

function SidebarItem({
  label,
  path,
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
      </NavLink>
    </li>
  )
}

export default SidebarItem