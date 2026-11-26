import { useEffect, useState } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { recursoRequest } from '../services/recursosService'
import { useVisibleRefresh } from './useVisibleRefresh'

type EstadoCreacion = { aviso: string | null; permitido: boolean }

const consultar = () => recursoRequest<EstadoCreacion>('/catalogos/asignaciones/estado-creacion', 'GET', undefined, true)

export function useEstadoCreacionCoordinador() {
  const { user } = useAuth()
  const coordinadorId = user?.role_code === 'COORDINADOR' ? user.id : undefined
  const [result, setResult] = useState<{ id: string; estado: EstadoCreacion }>()

  useEffect(() => {
    if (!coordinadorId) return
    let active = true
    void consultar().then((estado) => {
      if (active) setResult({ id: coordinadorId, estado })
    }).catch(() => { /* La actualización visible reintenta la consulta. */ })
    return () => { active = false }
  }, [coordinadorId])

  useVisibleRefresh(async (isActive) => {
    if (!coordinadorId) return
    try {
      const estado = await consultar()
      if (isActive()) setResult({ id: coordinadorId, estado })
    } catch { /* Conserva el último estado confirmado. */ }
  }, !!coordinadorId)

  return result?.id === coordinadorId ? result?.estado : undefined
}
