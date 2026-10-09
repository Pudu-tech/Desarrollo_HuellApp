/**
 * HuellApp · Formulario de creación de colegios.
 *
 * REGLAS
 * ------------------------------------------------------------
 * - Utiliza los mismos campos y catálogos que la edición.
 * - Valida la comuna seleccionada y normaliza opcionales antes de POST.
 * - El backend controla permisos, unicidad del RBD y auditoría atómica.
 * - Evita envíos simultáneos y conserva el formulario si la API falla.
 */

import { useEffect, useState, type FormEvent } from 'react'
import { getComunas } from '../../services/colegiosService'
import type { ColegioListItem, ComunaItem, RegionItem, TipoDependenciaItem } from '../../types/colegios'
import ColegioFields from './ColegioFields'
import { EMPTY_COLEGIO, normalizeColegio, validateColegio, type ColegioFormValues } from './colegioForm'

interface Props {
  regiones: RegionItem[]
  dependencias: TipoDependenciaItem[]
  onCreate: (data: ColegioFormValues) => Promise<ColegioListItem>
  onClose: () => void
}

/** Coordina la creación; no altera el formulario ni los endpoints de edición. */
function ColegioCreateForm({ regiones, dependencias, onCreate, onClose }: Props) {
  const [form, setForm] = useState<ColegioFormValues>({ ...EMPTY_COLEGIO })
  const [comunas, setComunas] = useState<ComunaItem[]>([])
  const [loadingComunas, setLoadingComunas] = useState(false)
  const [comunasError, setComunasError] = useState<string | null>(null)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)

  /** Descarta resultados obsoletos cuando se cambia rápidamente de región. */
  useEffect(() => {
    if (!form.region_id) {
      setComunas([])
      setComunasError(null)
      setLoadingComunas(false)
      return
    }
    let active = true
    setLoadingComunas(true)
    setComunas([])
    setComunasError(null)
    void getComunas(form.region_id)
      .then((items) => { if (active) setComunas(items) })
      .catch(() => { if (active) setComunasError('No se pudieron cargar las comunas. Selecciona nuevamente la región.') })
      .finally(() => { if (active) setLoadingComunas(false) })
    return () => { active = false }
  }, [form.region_id])

  /** Actualiza un campo sin duplicar reglas de normalización. */
  const change = <K extends keyof ColegioFormValues>(key: K, value: ColegioFormValues[K]) => {
    setForm((previous) => ({ ...previous, [key]: value }))
    setError(null)
  }

  /** Crea el colegio una sola vez y delega la sincronización del listado al padre. */
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (working) return
    setError(null)
    const validationError = validateColegio(form, comunas)
    if (validationError || loadingComunas || comunasError) {
      setError(validationError ?? 'Espera a que terminen de cargar las comunas.')
      return
    }
    setWorking(true)
    try {
      await onCreate(normalizeColegio(form))
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'No fue posible crear el colegio.')
    } finally {
      setWorking(false)
    }
  }

  return (
    <div className="schools-editor">
      <div className="schools-editor-heading">
        <div><h2>Crear colegio</h2><p>Registra un nuevo establecimiento educacional.</p></div>
        <button className="schools-secondary" type="button" onClick={onClose} disabled={working}>Volver al listado</button>
      </div>
      {error && <p className="schools-error" role="alert">{error}</p>}
      <form onSubmit={(event) => { void submit(event) }}>
        <fieldset className="schools-fieldset" disabled={working}>
          <ColegioFields
            values={form}
            regiones={regiones}
            comunas={comunas}
            dependencias={dependencias}
            loadingComunas={loadingComunas}
            comunasError={comunasError}
            change={change}
            onRegionChange={(regionId) => {
              setForm((previous) => ({ ...previous, region_id: regionId, comuna_id: '' }))
              setError(null)
            }}
          />
          {comunasError && <p className="schools-error" role="alert">{comunasError}</p>}
        </fieldset>
        <div className="schools-editor-actions">
          <button className="schools-primary" type="submit" disabled={working || loadingComunas || !!comunasError || !form.region_id}>
            {working ? 'Creando colegio...' : 'Crear colegio'}
          </button>
          <button className="schools-secondary" type="button" onClick={onClose} disabled={working}>Cancelar</button>
        </div>
      </form>
    </div>
  )
}

export default ColegioCreateForm
