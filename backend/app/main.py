"""
Punto de entrada principal del backend de HuellAPP.

Este módulo:
- Inicializa la aplicación FastAPI.
- Configura la metadata básica de la API.
- Configura CORS según variables de entorno.
- Registra middleware transversal.
- Registra los routers disponibles.
- Expone un endpoint raíz de verificación.

SECURITY:
- No se exponen credenciales ni información sensible.
- Swagger/OpenAPI se deshabilita automáticamente en producción.
- CORS solo permite orígenes declarados explícitamente.
- La lógica de negocio y seguridad se mantiene separada
  de este archivo para facilitar mantenimiento y auditoría.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.asignaciones import router as asignaciones_router
from app.api.audit import router as audit_router
from app.api.auth import router as auth_router
from app.api.colegios import router as colegios_router
from app.api.cursos import router as cursos_router
from app.api.health import router as health_router
from app.api.salas import router as salas_router
from app.api.users import router as users_router
from app.core.config import get_settings
from app.middleware.request_id import RequestIdMiddleware

settings = get_settings()


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="API backend del sistema HuellAPP.",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)


# ============================================================
# MIDDLEWARE
# ============================================================

# Genera un UUID único para cada petición HTTP.
app.add_middleware(RequestIdMiddleware)

# CORS se limita a los orígenes declarados en configuración.
# Se habilitan credenciales porque el frontend utilizará
# autenticación mediante encabezado Authorization.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# ROUTERS
# ============================================================

# Registra los endpoints relacionados con el estado del servicio.
app.include_router(health_router)

# Registra los endpoints protegidos relacionados con autenticación.
app.include_router(auth_router)

# Registra los endpoints relacionados con administración de usuarios.
app.include_router(users_router)

# Registra los endpoints de consulta de auditoría.
app.include_router(audit_router)

# Registra los endpoints relacionados con administración de colegios.
app.include_router(colegios_router)

# Registra los endpoints del módulo de cursos.
app.include_router(cursos_router)

# Registra los endpoints del módulo de salas.
app.include_router(salas_router)

# Registra los endpoints del módulo de asignaciones.
app.include_router(asignaciones_router)


@app.get("/", tags=["Root"])
async def root() -> dict[str, str]:
    """
    Entrega una respuesta mínima para identificar el servicio.

    Returns:
        dict[str, str]: Nombre y estado básico de la API.
    """

    return {
        "message": "HuellAPP API",
        "status": "running",
    }
