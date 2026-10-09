/**
 * HuellApp · Navegación accesible de la ficha del establecimiento.
 * Las flechas, Inicio y Fin recorren las pestañas autorizadas.
 * Cada panel conserva su estado después de su primera apertura.
 */
import { useRef } from 'react'

export type ColegioSection = 'informacion' | 'contactos' | 'cursos' | 'salas'
const COLEGIO_SECTIONS: Array<{ id: ColegioSection; label: string; permission?: string }> = [
  { id: 'informacion', label: 'Información general' },
  { id: 'contactos', label: 'Personas de contacto', permission: 'VIEW_SCHOOL_CONTACTS' },
  { id: 'cursos', label: 'Cursos', permission: 'VIEW_COURSES' },
  { id: 'salas', label: 'Salas', permission: 'VIEW_ROOMS' },
]

interface Props {
  value: ColegioSection
  permissions: string[]
  disabled: boolean
  onChange: (section: ColegioSection) => void
}

/** La autorización visual nunca sustituye los permisos validados en backend. */
export default function ColegioTabs({ value, permissions, disabled, onChange }: Props) {
  const refs = useRef<Array<HTMLButtonElement | null>>([])
  const sections = COLEGIO_SECTIONS.filter((section) => !section.permission || permissions.includes(section.permission))
  return <div role="tablist" aria-label="Secciones del colegio" className="schools-tabs">
    {sections.map((section, index) => <button key={section.id} type="button" role="tab"
      id={`school-tab-${section.id}`} aria-controls={`school-panel-${section.id}`}
      aria-selected={value === section.id} tabIndex={value === section.id ? 0 : -1}
      disabled={disabled} ref={(element) => { refs.current[index] = element }}
      onClick={() => onChange(section.id)} onKeyDown={(event) => {
        const next = event.key === 'ArrowRight' ? (index + 1) % sections.length
          : event.key === 'ArrowLeft' ? (index - 1 + sections.length) % sections.length
            : event.key === 'Home' ? 0 : event.key === 'End' ? sections.length - 1 : null
        if (next === null || disabled) return
        event.preventDefault()
        onChange(sections[next].id)
        refs.current[next]?.focus()
      }}>{section.label}</button>)}
  </div>
}
