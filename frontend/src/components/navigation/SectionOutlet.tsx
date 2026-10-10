import { useEffect } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import FormValidation from '../FormValidation'

/** Cada navegación abre la página desde su estado inicial y conserva la caché de datos. */
export default function SectionOutlet() {
  const location = useLocation()
  useEffect(() => {
    window.scrollTo({ top: 0, left: 0, behavior: 'instant' })
    document.querySelector('.app-content')?.scrollTo({ top: 0, left: 0, behavior: 'instant' })
  }, [location.key])
  return <FormValidation key={location.key}><Outlet /></FormValidation>
}
