import { spawnSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { stripVTControlCharacters } from 'node:util'

/**
 * Ejecutar desde frontend: npm.cmd run test:txt
 * También desde testing: node run-tests.mjs
 * Guarda el último resultado en frontend/.vitest/resultados.txt (UTF-8).
 * El reporte se reemplaza en cada ejecución e incluye pruebas aprobadas,
 * fallidas, tiempos y mensajes de error del proceso de Vitest.
 */
function ejecutarPruebas() {
  // Resuelve las rutas desde este archivo para no depender del directorio de la terminal.
  const frontend = fileURLToPath(new URL('../', import.meta.url))
  const vitest = fileURLToPath(new URL('../node_modules/vitest/vitest.mjs', import.meta.url))
  const reportDirectory = new URL('../.vitest/', import.meta.url)
  const reportFile = new URL('resultados.txt', reportDirectory)
  mkdirSync(reportDirectory, { recursive: true })

  // Ejecuta la instalación local sin shell; no necesita descargar paquetes ni queda en modo watch.
  const environment = { ...process.env, NO_COLOR: '1' }
  delete environment.FORCE_COLOR
  const startedAt = new Date().toLocaleString('es-CL', { timeZone: 'America/Santiago' })
  const result = spawnSync(process.execPath, [
    vitest, 'run', '--config', 'testing/vitest.config.ts', '--reporter=verbose',
  ], {
    cwd: frontend,
    env: environment,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
  })

  // Conservar stdout y stderr permite exportar los fallos; quitar escapes deja texto legible.
  const exitCode = result.status ?? 1
  const output = stripVTControlCharacters([
    result.stdout, result.stderr, result.error?.message,
    result.signal ? `Proceso interrumpido por señal: ${result.signal}` : '',
  ].filter(Boolean).join('\n'))
  const report = [
    'HuellApp - Reporte de pruebas unitarias (Vitest)',
    `Inicio (America/Santiago): ${startedAt}`,
    `Resultado: ${exitCode === 0 ? 'CORRECTO' : 'FALLO'}`,
    `Código de salida: ${exitCode}`,
    '', output, '',
  ].join('\n')
  writeFileSync(reportFile, report, 'utf8')
  process.stdout.write(report)
  console.log(`Reporte TXT: ${fileURLToPath(reportFile)}`)

  // Mantiene el fallo para que una terminal o una futura integración continua lo detecte.
  return exitCode
}

process.exitCode = ejecutarPruebas()
