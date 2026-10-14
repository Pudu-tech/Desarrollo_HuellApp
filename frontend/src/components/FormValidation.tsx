import { useId, type ReactNode, type FormEvent } from 'react'
import '../styles/form-validation.css'

type Field = HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement
const isField = (target: EventTarget): target is Field => target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement

/** Conserva las restricciones HTML y sustituye los globos nativos por avisos accesibles. */
export default function FormValidation({ children }: { children: ReactNode }) {
  const prefix = useId()
  function clear(event: FormEvent<HTMLDivElement>) {
    if (!isField(event.target) || !event.target.validity.valid) return
    const field = event.target
    const messageId = field.dataset.validationMessage
    if (!messageId) return
    document.getElementById(messageId)?.remove()
    field.removeAttribute('aria-invalid')
    const descriptions = (field.getAttribute('aria-describedby') || '').split(' ').filter(id => id && id !== messageId)
    if (descriptions.length) field.setAttribute('aria-describedby', descriptions.join(' '))
    else field.removeAttribute('aria-describedby')
    delete field.dataset.validationMessage
  }
  function invalid(event: FormEvent<HTMLDivElement>) {
    if (!isField(event.target)) return
    event.preventDefault()
    const field = event.target
    const form = field.form
    const fields = form ? Array.from(form.elements) : [field]
    const id = field.dataset.validationMessage || `${prefix}-field-${fields.indexOf(field)}`
    let message = document.getElementById(id)
    if (!message) {
      message = document.createElement('span')
      message.id = id
      message.className = 'huella-field-message'
      message.setAttribute('role', 'alert')
      field.insertAdjacentElement('afterend', message)
    }
    const validity = field.validity
    message.textContent = validity.valueMissing
      ? field instanceof HTMLSelectElement ? 'Selecciona una opción para continuar.' : field.type === 'checkbox' ? 'Marca esta opción para continuar.' : 'Completa este campo para continuar.'
      : validity.typeMismatch ? 'Ingresa un valor válido para este campo.'
      : validity.rangeUnderflow || validity.rangeOverflow ? 'El valor está fuera del rango permitido.'
      : validity.patternMismatch ? 'Revisa el formato de este campo.'
      : field.validationMessage || 'Revisa este campo para continuar.'
    field.dataset.validationMessage = id
    field.setAttribute('aria-invalid', 'true')
    const descriptions = new Set((field.getAttribute('aria-describedby') || '').split(' ').filter(Boolean))
    descriptions.add(id)
    field.setAttribute('aria-describedby', [...descriptions].join(' '))
    if (!form || form.querySelector(':invalid') === field) {
      field.focus({ preventScroll: true })
      field.scrollIntoView({ behavior: 'auto', block: 'center' })
    }
  }
  return <div onInvalidCapture={invalid} onInputCapture={clear} onChangeCapture={clear}>{children}</div>
}
