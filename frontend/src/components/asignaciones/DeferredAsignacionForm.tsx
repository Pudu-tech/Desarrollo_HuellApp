/**
 * HuellApp · Carga diferida del formulario de instancias.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Cargar el formulario bajo demanda y mostrar la espera mientras se descarga.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Evita incorporar el formulario completo en la carga inicial del listado.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import LoadingIndicator from '../LoadingIndicator'
import { lazy, Suspense, type ComponentProps } from 'react'
import type AsignacionCreateForm from './AsignacionCreateForm'

const Form = lazy(() => import('./AsignacionCreateForm'))

export default function DeferredAsignacionForm(props: ComponentProps<typeof AsignacionCreateForm>) {
  return <Suspense fallback={<LoadingIndicator />}><Form {...props} /></Suspense>
}
