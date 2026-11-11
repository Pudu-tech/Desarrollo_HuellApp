/**
 * HuellApp · Inicio del monitor.
 *
 * RESPONSABILIDADES
 * ------------------------------------------------------------
 * - Reutilizar la página de inicio común para la ruta del monitor.
 *
 * ESTADO ACTUAL
 * ------------------------------------------------------------
 * - Reexporta InicioPage y evita mantener una segunda implementación.
 *
 * SECURITY
 * ------------------------------------------------------------
 * La interfaz orienta la navegación y las acciones visibles. FastAPI valida
 * la identidad, los permisos y las reglas de las operaciones protegidas.
 */
export { default } from './InicioPage'
