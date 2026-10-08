import { lazy, Suspense, type ComponentProps } from 'react'
import type AsignacionCreateForm from './AsignacionCreateForm'

const Form = lazy(() => import('./AsignacionCreateForm'))

export default function DeferredAsignacionForm(props: ComponentProps<typeof AsignacionCreateForm>) {
  return <Suspense fallback={<p role="status" className="assignments-feedback">Cargando formulario…</p>}><Form {...props} /></Suspense>
}
