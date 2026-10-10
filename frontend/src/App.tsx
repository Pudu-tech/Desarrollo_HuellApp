import LoadingIndicator from './components/LoadingIndicator'
import { lazy, Suspense, type ComponentType } from 'react'
/**
 * HuellApp
 * Configuración principal de rutas con separación por rol.
 *
 * ROLES
 * ------------------------------------------------------------
 * SUPERADMIN
 * - Inicio
 * - Usuarios
 * - Colegios
 * - Cursos y Salas dentro de la ficha de Colegios
 * - Asignaciones
 * - Auditoría
 *
 * DIRECTIVA
 * - Inicio
 * - Usuarios
 * - Colegios
 * - Cursos y Salas dentro de la ficha de Colegios
 * - Asignaciones
 *
 * COORDINADOR
 * - Inicio
 * - Asignaciones
 *
 * MONITOR
 * - Página propia de Monitor
 * - Mis asignaciones
 *
 * AUTENTICACIÓN
 * ------------------------------------------------------------
 * Rutas públicas:
 * - /
 * - /login
 * - /recuperar-password
 * - /restablecer-password
 * - /establecer-password
 *
 * Rutas autenticadas:
 * - /app/*
 *
 * SECURITY
 * ------------------------------------------------------------
 * Las restricciones de frontend controlan navegación y
 * visibilidad de páginas.
 *
 * FastAPI continúa siendo la fuente real de autorización
 * mediante roles, permisos y reglas de negocio.
 */

import {
  BrowserRouter,
  Navigate,
  Route,
  Routes,
} from 'react-router-dom'

import { AuthProvider } from './contexts/AuthContext'

import AppLayout from './layouts/AppLayout'
import MonitorLayout from './layouts/MonitorLayout'

const AccesoDenegadoPage = loadPage(() => import('./pages/AccesoDenegadoPage'))
const AsignacionDetallePage = loadPage(() => import('./pages/AsignacionDetallePage'))
const AsignacionesPage = loadPage(() => import('./pages/AsignacionesPage'))
const AsistenciaPage = loadPage(() => import('./pages/AsistenciaPage'))
const AuditoriaPage = loadPage(() => import('./pages/AuditoriaPage'))
const ColegiosPage = loadPage(() => import('./pages/ColegiosPage'))
const CatalogoAcademicoPage = loadPage(() => import('./pages/CatalogoAcademicoPage'))
const InvitacionParticipacionPage = loadPage(() => import('./pages/InvitacionParticipacionPage'))
const MisParticipacionesPage = loadPage(() => import('./pages/MisParticipacionesPage'))
const MiParticipacionPage = loadPage(() => import('./pages/MiParticipacionPage'))
const EstablecerPasswordPage = loadPage(() => import('./pages/EstablecerPasswordPage'))
const InicioPage = loadPage(() => import('./pages/InicioPage'))
import LoginPage from './pages/LoginPage'
const MonitorAsignacionDetallePage = loadPage(() => import('./pages/MonitorAsignacionDetallePage'))
const MonitorAsignacionesPage = loadPage(() => import('./pages/MonitorAsignacionesPage'))
const MonitorPage = loadPage(() => import('./pages/MonitorPage'))
const NotFoundPage = loadPage(() => import('./pages/NotFoundPage'))
const RecuperarPasswordPage = loadPage(() => import('./pages/RecuperarPasswordPage'))
const RestablecerPasswordPage = loadPage(() => import('./pages/RestablecerPasswordPage'))
const UsuariosPage = loadPage(() => import('./pages/UsuariosPage'))

import AppEntryRoute from './routes/AppEntryRoute'
import ProtectedRoute from './routes/ProtectedRoute'
import RoleRoute from './routes/RoleRoute'


function loadPage(load: () => Promise<{ default: ComponentType }>) {
  const Page = lazy(load)
  return function LoadedPage() {
    return <Suspense fallback={<LoadingIndicator />}><Page /></Suspense>
  }
}

function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>

          {/* ==================================================
              AUTENTICACIÓN - RUTAS PÚBLICAS
              ================================================== */}

          <Route
            path="/"
            element={<LoginPage />}
          />
          <Route path="/responder-participacion" element={<InvitacionParticipacionPage />} />

          <Route
            path="/login"
            element={
              <Navigate
                to="/"
                replace
              />
            }
          />

          <Route
            path="/recuperar-password"
            element={<RecuperarPasswordPage />}
          />

          <Route
            path="/restablecer-password"
            element={<RestablecerPasswordPage />}
          />

          <Route
            path="/establecer-password"
            element={<EstablecerPasswordPage />}
          />


          {/* ==================================================
              ENTRADA A ZONA AUTENTICADA
              ================================================== */}

          <Route
            path="/app"
            element={
              <ProtectedRoute>
                <AppEntryRoute />
              </ProtectedRoute>
            }
          />

          <Route
            path="/app/acceso-denegado"
            element={
              <ProtectedRoute>
                <AccesoDenegadoPage />
              </ProtectedRoute>
            }
          />


          {/* ==================================================
              SUPERADMIN / DIRECTIVA / COORDINADOR
              ================================================== */}

          <Route
            path="/app"
            element={
              <RoleRoute
                allowedRoles={[
                  'SUPERADMIN',
                  'DIRECTIVA',
                  'COORDINADOR',
                ]}
              >
                <AppLayout />
              </RoleRoute>
            }
          >

            <Route
              path="inicio"
              element={<InicioPage />}
            />
            <Route path="catalogo-academico" element={<RoleRoute allowedRoles={['SUPERADMIN', 'DIRECTIVA']}><CatalogoAcademicoPage /></RoleRoute>} />
            <Route path="mis-asignaciones" element={<MisParticipacionesPage />} />
            <Route path="mis-asignaciones/:asignacionId" element={<MiParticipacionPage />} />

            <Route
              path="asignaciones"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                    'COORDINADOR',
                  ]}
                >
                  <AsignacionesPage />
                </RoleRoute>
              }
            />

            <Route
              path="asignaciones/:asignacionId"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                    'COORDINADOR',
                  ]}
                >
                  <AsignacionDetallePage />
                </RoleRoute>
              }
            />

            <Route
              path="usuarios"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                  ]}
                >
                  <UsuariosPage />
                </RoleRoute>
              }
            />

            <Route
              path="colegios"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                  ]}
                >
                  <ColegiosPage />
                </RoleRoute>
              }
            />

            <Route
              path="cursos"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                  ]}
                >
                  <Navigate to="/app/colegios" replace />
                </RoleRoute>
              }
            />

            <Route
              path="salas"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                  ]}
                >
                  <Navigate to="/app/colegios" replace />
                </RoleRoute>
              }
            />

            <Route
              path="asistencia"
              element={<RoleRoute allowedRoles={['SUPERADMIN', 'DIRECTIVA', 'COORDINADOR']}><AsistenciaPage /></RoleRoute>}
            />
            <Route
              path="auditoria"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
                    'DIRECTIVA',
                  ]}
                >
                  <AuditoriaPage />
                </RoleRoute>
              }
            />

          </Route>


          {/* ==================================================
              MONITOR
              ================================================== */}

          <Route
            path="/app/monitor"
            element={
              <RoleRoute
                allowedRoles={[
                  'MONITOR',
                ]}
              >
                <MonitorLayout />
              </RoleRoute>
            }
          >

            <Route
              index
              element={<MonitorPage />}
            />

            <Route
              path="asignaciones"
              element={<MonitorAsignacionesPage />}
            />
            <Route path="asistencia" element={<AsistenciaPage />} />

            <Route
              path="asignaciones/:asignacionId"
              element={<MonitorAsignacionDetallePage />}
            />

          </Route>


          {/* ==================================================
              RUTA NO ENCONTRADA
              ================================================== */}

          <Route
            path="*"
            element={<NotFoundPage />}
          />

        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}

export default App
