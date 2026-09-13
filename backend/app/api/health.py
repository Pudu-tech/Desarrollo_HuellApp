"""
Endpoints de salud del backend de HuellAPP.

Este módulo permite verificar:
- Que la API FastAPI se encuentre operativa.
- Que el backend pueda conectarse correctamente a Supabase.

SECURITY:
- No se exponen credenciales ni claves sensibles.
- La respuesta de conexión solo informa si Supabase está disponible.
- Los errores internos no se retornan directamente al cliente.
"""

from fastapi import APIRouter, HTTPException, status

from app.core.supabase import get_supabase_client


router = APIRouter(
    prefix="/health",
    tags=["Health"],
)


@router.get("")
async def health_check() -> dict[str, str]:
    """
    Verifica que la API de HuellAPP se encuentre operativa.

    Returns:
        dict[str, str]: Estado básico del servicio.
    """

    return {
        "status": "ok",
        "service": "HuellAPP API",
    }


@router.get("/supabase")
async def supabase_health_check() -> dict[str, str]:
    """
    Verifica la comunicación entre FastAPI y Supabase.

    Se realiza una consulta mínima sobre la tabla `roles`.
    No se retorna información de los registros porque el objetivo
    de este endpoint es únicamente validar conectividad.

    Returns:
        dict[str, str]: Estado de conexión con Supabase.

    Raises:
        HTTPException: Si no es posible comunicarse con Supabase.

    SECURITY:
        Los detalles internos de la excepción no se retornan al cliente
        para evitar exponer información de infraestructura o credenciales.
    """

    try:
        supabase = get_supabase_client()

        # Consulta mínima para comprobar que el backend puede comunicarse
        # correctamente con la base de datos.
        supabase.table("roles").select("id").limit(1).execute()

        return {
            "status": "ok",
            "database": "supabase",
        }

    except Exception:
        # SECURITY:
        # No devolvemos el contenido real de la excepción porque podría
        # revelar datos internos de infraestructura.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No fue posible conectar con Supabase.",
        )