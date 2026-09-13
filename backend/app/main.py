"""
Punto de entrada principal del backend de HuellAPP.

Este módulo:
- Inicializa la aplicación FastAPI.
- Configura la metadata básica de la API.
- Registra middleware transversal.
- Registra los routers disponibles.
- Expone un endpoint raíz de verificación.

SECURITY:
- No se exponen credenciales ni información sensible.
- La lógica de negocio y seguridad se mantiene separada
  de este archivo para facilitar mantenimiento y auditoría.
"""

from fastapi import FastAPI

from app.api.audit import router as audit_router
from app.api.auth import router as auth_router
from app.api.colegios import router as colegios_router
from app.api.health import router as health_router
from app.api.users import router as users_router
from app.core.config import get_settings
from app.middleware.request_id import RequestIdMiddleware
from app.api.cursos import router as cursos_router
from app.api.salas import router as salas_router

settings = get_settings()


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="API backend del sistema HuellAPP.",
)


# ============================================================
# MIDDLEWARE
# ============================================================

# Genera un UUID único para cada petición HTTP.
app.add_middleware(RequestIdMiddleware)


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

# Registrar endpoints del módulo de cursos.
app.include_router(cursos_router)

# Registrar endpoints del módulo de salas.
app.include_router(salas_router)

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