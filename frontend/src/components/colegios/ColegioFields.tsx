/**
 * HuellApp · Campos compartidos de creación y edición de colegios.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Los selectores usan catálogos reales entregados por el backend.
 * - Al cambiar de región, el contenedor limpia la comuna seleccionada.
 * - Este componente es presentacional: no realiza solicitudes ni guarda datos.
 */

import type { ColegioFormValues } from './colegioForm'
import type { ComunaItem, RegionItem, TipoDependenciaItem } from '../../types/colegios'

interface Props {
  values: ColegioFormValues
  regiones: RegionItem[]
  comunas: ComunaItem[]
  dependencias: TipoDependenciaItem[]
  loadingComunas: boolean
  comunasError: string | null
  change: <K extends keyof ColegioFormValues>(key: K, value: ColegioFormValues[K]) => void
  onRegionChange: (regionId: string) => void
}

/** Renderiza los mismos campos y restricciones visuales en ambos formularios. */
function ColegioFields({ values, regiones, comunas, dependencias, loadingComunas, comunasError, change, onRegionChange }: Props) {
  return (
    <>
      <section className="schools-form-section">
        <h3>Información general</h3>
        <div className="schools-form-grid">
          <label className="schools-field-wide">Nombre del colegio *<input required maxLength={200} value={values.nombre} onChange={(e) => change('nombre', e.target.value)} /></label>
          <label>RBD<input value={values.rbd ?? ''} onChange={(e) => change('rbd', e.target.value)} /></label>
          <label>Dependencia<select value={values.tipo_dependencia_id ?? ''} onChange={(e) => change('tipo_dependencia_id', e.target.value || null)}>
            <option value="">Sin especificar</option>{dependencias.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}
          </select></label>
          <label className="schools-field-wide">Descripción<textarea rows={3} value={values.descripcion ?? ''} onChange={(e) => change('descripcion', e.target.value)} /></label>
        </div>
      </section>
      <section className="schools-form-section">
        <h3>Ubicación</h3>
        <div className="schools-form-grid">
          <label>Región *<select required value={values.region_id} onChange={(e) => onRegionChange(e.target.value)}>
            <option value="">Seleccionar región</option>{regiones.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}
          </select></label>
          <label>Comuna *<select required value={values.comuna_id} disabled={!values.region_id || loadingComunas || !!comunasError} onChange={(e) => change('comuna_id', e.target.value)}>
            <option value="">{loadingComunas ? 'Cargando comunas...' : 'Seleccionar comuna'}</option>{comunas.map((item) => <option key={item.id} value={item.id}>{item.nombre}</option>)}
          </select></label>
          <label className="schools-field-wide">Dirección *<input required value={values.direccion} onChange={(e) => change('direccion', e.target.value)} /></label>
          <label>Número<input value={values.numero ?? ''} onChange={(e) => change('numero', e.target.value)} /></label>
          <label>Complemento<input value={values.complemento ?? ''} onChange={(e) => change('complemento', e.target.value)} /></label>
          <label>Código postal<input value={values.codigo_postal ?? ''} onChange={(e) => change('codigo_postal', e.target.value)} /></label>
        </div>
      </section>
      <section className="schools-form-section">
        <h3>Datos de contacto del colegio</h3>
        <div className="schools-form-grid">
          <label>Teléfono<input type="tel" value={values.telefono ?? ''} onChange={(e) => change('telefono', e.target.value)} /></label>
          <label>Correo del colegio<input type="email" value={values.email ?? ''} onChange={(e) => change('email', e.target.value)} /></label>
          <label className="schools-field-wide">Sitio web<input value={values.sitio_web ?? ''} onChange={(e) => change('sitio_web', e.target.value)} /></label>
        </div>
      </section>
    </>
  )
}

export default ColegioFields
