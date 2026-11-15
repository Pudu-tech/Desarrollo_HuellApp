"""HuellApp · Metadatos de contexto para operaciones auditadas.

Centraliza los datos comunes de request usados por RPC de escritura.
"""
from fastapi import Request


def request_rpc_context(request: Request) -> dict:
    """Construye metadatos comunes de auditoría para una solicitud HTTP."""
    request_id_raw = getattr(request.state, "request_id", None)
    return {
        "request_id": str(request_id_raw) if request_id_raw is not None else None,
        "ip_address": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
    }
