"""
Endpoints para consulta de registros de auditoría de HuellAPP.

Los registros de auditoría son append-only a nivel de base de datos.
Desde esta API únicamente pueden ser consultados.

SECURITY:
- Requiere el permiso VIEW_AUDIT_LOGS.
- No existe endpoint para modificar o eliminar auditorías.
- Se limita la cantidad máxima de registros por solicitud.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.audit import AuditLogItem
from app.schemas.auth import AuthenticatedUser


router = APIRouter(
    prefix="/audit",
    tags=["Audit"],
)


@router.get(
    "",
    response_model=list[AuditLogItem],
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "El usuario no posee el permiso VIEW_AUDIT_LOGS.",
        },
        500: {
            "description": "Error interno al obtener los registros de auditoría.",
        },
    },
)
async def list_audit_logs(
    limit: int = Query(
        default=50,
        ge=1,
        le=100,
        description="Cantidad máxima de registros a retornar.",
    ),
    offset: int = Query(
        default=0,
        ge=0,
        description="Cantidad de registros a omitir.",
    ),
    action: str | None = Query(
        default=None,
        description="Filtra por acción de auditoría.",
    ),
    entity_type: str | None = Query(
        default=None,
        description="Filtra por tipo de entidad.",
    ),
    actor_user_id: UUID | None = Query(
        default=None,
        description="Filtra por usuario que ejecutó la acción.",
    ),
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_AUDIT_LOGS")
    ),
) -> list[AuditLogItem]:
    """
    Obtiene registros de auditoría ordenados desde el más reciente.

    Requiere:
        VIEW_AUDIT_LOGS

    Filtros opcionales:
        - action
        - entity_type
        - actor_user_id

    Paginación:
        - limit: máximo 100 registros.
        - offset: posición inicial.

    SECURITY:
        - No permite escritura.
        - Los permisos se validan en backend.
        - El frontend no determina quién puede acceder.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. Construir consulta base.
        # --------------------------------------------------------
        query = (
            supabase.table("audit_logs")
            .select(
                """
                id,
                actor_user_id,
                actor_role_id,
                action,
                entity_type,
                entity_id,
                old_values,
                new_values,
                description,
                request_id,
                ip_address,
                user_agent,
                source,
                created_at
                """
            )
        )

        # --------------------------------------------------------
        # 2. Aplicar filtros opcionales.
        #
        # Los filtros se realizan mediante el cliente Supabase,
        # evitando construir SQL dinámico manualmente.
        # --------------------------------------------------------
        if action:
            query = query.eq(
                "action",
                action.strip().upper(),
            )

        if entity_type:
            query = query.eq(
                "entity_type",
                entity_type.strip().upper(),
            )

        if actor_user_id:
            query = query.eq(
                "actor_user_id",
                str(actor_user_id),
            )

        # --------------------------------------------------------
        # 3. Ordenar y paginar.
        #
        # Supabase/PostgREST utiliza rangos inclusivos.
        # Por ejemplo:
        # offset=0, limit=50 -> range(0, 49)
        # --------------------------------------------------------
        end_index = offset + limit - 1

        response = (
            query
            .order(
                "created_at",
                desc=True,
            )
            .range(
                offset,
                end_index,
            )
            .execute()
        )

        # --------------------------------------------------------
        # 4. Validar salida con Pydantic.
        # --------------------------------------------------------
        return [
            AuditLogItem.model_validate(item)
            for item in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        # SECURITY:
        # No exponemos mensajes internos de Supabase/PostgreSQL
        # al cliente.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener los registros de auditoría.",
        )