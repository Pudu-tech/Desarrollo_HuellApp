"""
Servicio de auditoría de HuellAPP.

Centraliza la creación de registros en public.audit_logs.

SECURITY:
- Nunca deben enviarse contraseñas, tokens, secretos ni credenciales.
- El actor debe provenir de una sesión autenticada validada.
- Los errores de auditoría no deben exponer detalles internos.
"""

from typing import Any
from uuid import UUID

from fastapi import Request

from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser


SENSITIVE_AUDIT_KEYS = {
    "password",
    "access_token",
    "refresh_token",
    "token",
    "secret",
    "api_key",
    "authorization",
}


def _sanitize_audit_values(
    values: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """
    Elimina campos sensibles antes de persistir datos de auditoría.

    Args:
        values:
            Diccionario original a registrar.

    Returns:
        dict | None:
            Copia saneada sin claves sensibles.
    """

    if values is None:
        return None

    sanitized: dict[str, Any] = {}

    for key, value in values.items():
        if key.lower() in SENSITIVE_AUDIT_KEYS:
            continue

        sanitized[key] = value

    return sanitized


async def write_audit_log(
    *,
    request: Request,
    actor: AuthenticatedUser,
    action: str,
    entity_type: str,
    entity_id: UUID | None,
    old_values: dict[str, Any] | None = None,
    new_values: dict[str, Any] | None = None,
    description: str | None = None,
    source: str = "WEB",
) -> None:
    """
    Registra una acción relevante en public.audit_logs.

    Args:
        request:
            Request HTTP actual, utilizado para obtener IP,
            User-Agent y request_id cuando esté disponible.

        actor:
            Usuario autenticado que ejecutó la acción.

        action:
            Código estable de la acción.
            Ej.: CREATE_USER, UPDATE_USER.

        entity_type:
            Tipo de entidad afectada.
            Ej.: USER.

        entity_id:
            UUID de la entidad afectada.

        old_values:
            Valores anteriores relevantes.

        new_values:
            Valores posteriores relevantes.

        description:
            Descripción legible de la operación.

        source:
            Origen de la acción. Por defecto WEB.

    SECURITY:
        - Nunca registra contraseñas ni tokens.
        - El rol del actor se resuelve desde base de datos.
        - Los datos sensibles son saneados antes del insert.
    """

    supabase = get_supabase_client()

    # ------------------------------------------------------------
    # Resolver rol real del actor.
    #
    # audit_logs almacena actor_role_id, no el código textual.
    # ------------------------------------------------------------
    role_response = (
        supabase.table("roles")
        .select("id")
        .eq("codigo", actor.role_code)
        .single()
        .execute()
    )

    actor_role_id = role_response.data["id"]

    # ------------------------------------------------------------
    # Metadatos de request.
    # ------------------------------------------------------------
    client_ip = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    request_id_raw = getattr(request.state, "request_id", None)

    request_id = (
        str(request_id_raw)
        if request_id_raw is not None
        else None
    )

    audit_data = {
        "actor_user_id": str(actor.id),
        "actor_role_id": actor_role_id,
        "action": action,
        "entity_type": entity_type,
        "entity_id": str(entity_id) if entity_id else None,
        "old_values": _sanitize_audit_values(old_values),
        "new_values": _sanitize_audit_values(new_values),
        "description": description,
        "request_id": request_id,
        "ip_address": client_ip,
        "user_agent": user_agent,
        "source": source,
    }

    (
        supabase.table("audit_logs")
        .insert(audit_data)
        .execute()
    )