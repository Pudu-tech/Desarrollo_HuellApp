"""
Schemas utilizados para exponer registros de auditoría.

SECURITY:
- Los registros de auditoría son de solo lectura desde la API.
- No se exponen secretos, contraseñas ni tokens.
- Los valores antiguos y nuevos provienen del servicio de auditoría,
  que sanitiza datos sensibles antes de almacenarlos.
"""

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel


class AuditLogItem(BaseModel):
    """
    Representa un registro individual de auditoría.
    """

    id: UUID

    actor_user_id: UUID | None = None
    actor_role_id: UUID | None = None

    action: str
    entity_type: str
    entity_id: UUID | None = None

    old_values: dict[str, Any] | None = None
    new_values: dict[str, Any] | None = None

    description: str | None = None

    request_id: UUID | None = None
    ip_address: str | None = None
    user_agent: str | None = None

    source: str

    created_at: datetime