import LoadingIndicator from '../LoadingIndicator'
import { lazy, Suspense, type ComponentProps } from 'react'
import type AsignacionCreateForm from './AsignacionCreateForm'

const Form = lazy(() => import('./AsignacionCreateForm'))

export default function DeferredAsignacionForm(props: ComponentProps<typeof AsignacionCreateForm>) {
  return <Suspense fallback={<LoadingIndicator />}><Form {...props} /></Suspense>
}
