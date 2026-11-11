/**
 * HuellApp · Configuración de Vite.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Habilitar el plugin React para desarrollo y compilación del frontend.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Configuración consumida por Vite, separada del código de las páginas.
 *
 * SECURITY
 * ------------------------------------------------------------
 * Las variables públicas de Vite pueden terminar en el bundle; no incluir secretos.
 */
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
})
