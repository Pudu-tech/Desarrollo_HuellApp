"""
Middleware para generar un identificador único por petición HTTP.

Cada request recibido por HuellAPP obtiene un UUID generado por el backend.

Este identificador permite:
- correlacionar una petición con registros de auditoría;
- facilitar diagnóstico de errores;
- mejorar trazabilidad entre frontend, backend y logs.

SECURITY:
- El identificador es generado exclusivamente por el backend.
- No se confía en valores X-Request-ID enviados por clientes externos.
- El UUID no contiene información personal ni sensible.
"""

from uuid import uuid4

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response


class RequestIdMiddleware(BaseHTTPMiddleware):
    """
    Asigna un UUID único a cada petición HTTP.

    El identificador queda disponible durante toda la petición mediante:

        request.state.request_id

    También se devuelve al cliente en:

        X-Request-ID
    """

    async def dispatch(
        self,
        request: Request,
        call_next,
    ) -> Response:
        """
        Procesa una petición y agrega su identificador de trazabilidad.
        """

        # Generamos el identificador dentro del servidor.
        # No reutilizamos valores proporcionados por el cliente.
        request_id = uuid4()

        # Permite que servicios como auditoría accedan al mismo UUID.
        request.state.request_id = request_id

        # Continúa con el procesamiento normal de FastAPI.
        response = await call_next(request)

        # Devuelve el identificador para facilitar soporte y trazabilidad.
        response.headers["X-Request-ID"] = str(request_id)

        return response