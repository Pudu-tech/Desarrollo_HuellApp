import { describe, expect, test } from 'vitest'
import { isRoleCode } from '../../src/utils/roles'

describe('isRoleCode', () => {
  test.each(['SUPERADMIN', 'DIRECTIVA', 'COORDINADOR', 'MONITOR'])('reconoce el rol %s', role => {
    expect(isRoleCode(role)).toBe(true)
  })

  // Verificamos el contrato público, sin simular la API ni confundir visibilidad con autorización.
  test.each(['', 'ADMIN', 'monitor', 'Monitor', ' MONITOR', 'MONITOR ', 'COORDINADOR_EXTRA'])(
    'rechaza el código desconocido o alterado "%s"', role => {
      expect(isRoleCode(role)).toBe(false)
    },
  )
})
