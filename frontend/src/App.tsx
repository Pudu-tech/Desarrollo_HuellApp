/**
 * HuellAPP
 * Configuración principal de rutas con separación por rol.
 *
 * ROLES
 * ------------------------------------------------------------
 * SUPERADMIN
 * - Inicio
 * - Usuarios
 * - Colegios
 * - Cursos
 * - Salas
 * - Asignaciones
 * - Auditoría
 *
 * DIRECTIVA
 * - Inicio
 * - Usuarios
 * - Colegios
 * - Cursos
 * - Salas
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

import AccesoDenegadoPage from './pages/AccesoDenegadoPage'
import AsignacionDetallePage from './pages/AsignacionDetallePage'
import AsignacionesPage from './pages/AsignacionesPage'
import AuditoriaPage from './pages/AuditoriaPage'
import ColegiosPage from './pages/ColegiosPage'
import CursosPage from './pages/CursosPage'
import InicioPage from './pages/InicioPage'
import LoginPage from './pages/LoginPage'
import MonitorAsignacionDetallePage from './pages/MonitorAsignacionDetallePage'
import MonitorAsignacionesPage from './pages/MonitorAsignacionesPage'
import MonitorPage from './pages/MonitorPage'
import NotFoundPage from './pages/NotFoundPage'
import RecuperarPasswordPage from './pages/RecuperarPasswordPage'
import RestablecerPasswordPage from './pages/RestablecerPasswordPage'
import SalasPage from './pages/SalasPage'
import UsuariosPage from './pages/UsuariosPage'

import AppEntryRoute from './routes/AppEntryRoute'
import ProtectedRoute from './routes/ProtectedRoute'
import RoleRoute from './routes/RoleRoute'


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
                  <CursosPage />
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
                  <SalasPage />
                </RoleRoute>
              }
            />

            <Route
              path="auditoria"
              element={
                <RoleRoute
                  allowedRoles={[
                    'SUPERADMIN',
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