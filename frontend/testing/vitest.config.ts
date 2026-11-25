import { fileURLToPath } from 'node:url'
import { defineConfig, mergeConfig } from 'vitest/config'
import viteConfig from '../vite.config.ts'

/**
 * Primera etapa: sortList, dateSortValue, ordenarPorFecha, colegiosDisponibles e isRoleCode.
 * Desde frontend: npm run test (observación), npm run test:run (una ejecución),
 * npm run test:types (comprobación estática; Vitest solo transforma TypeScript).
 * npm run test:txt ejecuta una vez y exporta el detalle a .vitest/resultados.txt.
 * En PowerShell con scripts restringidos se puede usar npm.cmd en lugar de npm.
 *
 * Guías oficiales revisadas:
 * https://vitest.dev/guide/
 * https://vitest.dev/guide/learn/writing-tests
 * https://vitest.dev/guide/environment
 *
 * Los casos importan funciones reales y comprueban resultados observables con datos
 * deterministas. No se necesita setupFiles: no hay DOM, mocks ni recursos que limpiar.
 * Para ampliar esta etapa, agregar archivos .test.ts en testing/unit y ejecutar ambos
 * comandos de comprobación. Los tests node:test de tests/ siguen fuera de esta selección.
 */
// Reutiliza los plugins de Vite para que las importaciones se transformen igual que en la aplicación.
export default mergeConfig(viteConfig, defineConfig({
  // La raíz no depende del directorio desde el que se invoque la configuración.
  root: fileURLToPath(new URL('../', import.meta.url)),
  test: {
    // Estas cinco funciones no necesitan DOM, credenciales ni servicios externos.
    environment: 'node',
    // Migración gradual: los archivos existentes con node:test conservan su runner.
    include: ['testing/unit/**/*.test.ts'],
    // Importar describe/test/expect explícitamente evita añadir globales al código de producción.
    globals: false,
    // Un .only accidental debe fallar en la ejecución automatizada.
    allowOnly: !process.env.CI,
  },
}))
