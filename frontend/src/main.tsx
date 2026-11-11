/**
 * HuellApp · Inicio de la aplicación React.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Montar App en el elemento raíz y cargar los estilos globales.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Punto de entrada utilizado por Vite.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import App from './App'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)