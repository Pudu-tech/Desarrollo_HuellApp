"""
Endpoints de administración de salas en HuellAPP.

Funciones disponibles:
- listar salas;
- obtener sala por UUID;
- crear sala;
- modificar sala;
- activar sala;
- desactivar sala.

SECURITY:
- Todos los endpoints utilizan permisos RBAC.
- created_by y updated_by provienen del usuario autenticado.
- colegio_id siempre se valida contra un colegio existente y activo.
- Las operaciones sensibles quedan registradas en auditoría.
- No existe eliminación física de salas desde esta API.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.salas import (
    SalaCreate,
    SalaListItem,
    SalaUpdate,
)


router = APIRouter(
    prefix="/salas",
    tags=["Salas"],
)


# ============================================================
# CAMPOS CONSULTADOS
# ============================================================

SALA_SELECT = """
id,
colegio_id,
nombre,
descripcion,
capacidad,
ubicacion,
activo,
created_at,
updated_at
"""


# ============================================================
# FUNCIONES INTERNAS
# ============================================================


def _request_rpc_context(request: Request) -> dict:
    """
    Construye los metadatos comunes para las RPC de escritura.
    """

    request_id_raw = getattr(request.state, "request_id", None)

    return {
        "request_id": (
            str(request_id_raw)
            if request_id_raw is not None
            else None
        ),
        "ip_address": (
            request.client.host
            if request.client
            else None
        ),
        "user_agent": request.headers.get("user-agent"),
    }


def _obtener_sala_resultado(
    supabase,
    *,
    sala_id: UUID,
) -> SalaListItem:
    """
    Recupera una sala no eliminada usando el contrato público.
    """

    response = (
        supabase.table("salas")
        .select(SALA_SELECT)
        .eq("id", str(sala_id))
        .is_("deleted_at", "null")
        .single()
        .execute()
    )

    return SalaListItem.model_validate(response.data)






def _payload_a_dict(
    payload: SalaCreate | SalaUpdate,
) -> dict:
    """
    Convierte un modelo Pydantic en datos compatibles con Supabase.

    exclude_unset permite que PATCH modifique únicamente
    los campos enviados por el cliente.
    """

    return payload.model_dump(
        exclude_unset=True,
        mode="json",
    )


def _obtener_colegio_activo(
    supabase,
    *,
    colegio_id: UUID,
) -> dict:
    """
    Valida que el colegio exista, no esté eliminado
    lógicamente y se encuentre activo.
    """

    response = (
        supabase.table("colegios")
        .select("id,nombre,activo,deleted_at")
        .eq("id", str(colegio_id))
        .maybe_single()
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El colegio seleccionado no existe.",
        )

    if response.data.get("deleted_at") is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El colegio seleccionado no existe.",
        )

    if response.data["activo"] is not True:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El colegio seleccionado se encuentra inactivo.",
        )

    return response.data




# ============================================================
# LISTAR SALAS
# ============================================================


@router.get(
    "",
    response_model=list[SalaListItem],
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_ROOMS.",
        },
        500: {
            "description": "Error interno al obtener salas.",
        },
    },
)
async def listar_salas(
    colegio_id: UUID | None = None,
    activo: bool | None = None,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_ROOMS")
    ),
) -> list[SalaListItem]:
    """
    Lista salas no eliminadas lógicamente.

    Filtros opcionales:
    - colegio_id;
    - activo.
    """

    supabase = get_supabase_client()

    try:
        query = (
            supabase.table("salas")
            .select(SALA_SELECT)
            .is_("deleted_at", "null")
        )

        if colegio_id is not None:
            query = query.eq(
                "colegio_id",
                str(colegio_id),
            )

        if activo is not None:
            query = query.eq(
                "activo",
                activo,
            )

        response = (
            query
            .order("nombre")
            .execute()
        )

        return [
            SalaListItem.model_validate(item)
            for item in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener las salas.",
        )


# ============================================================
# OBTENER SALA
# ============================================================


@router.get(
    "/{sala_id}",
    response_model=SalaListItem,
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_ROOMS.",
        },
        404: {
            "description": "Sala no encontrada.",
        },
        500: {
            "description": "Error interno al obtener la sala.",
        },
    },
)
async def obtener_sala(
    sala_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_ROOMS")
    ),
) -> SalaListItem:
    """
    Obtiene una sala no eliminada lógicamente por UUID.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("salas")
            .select(SALA_SELECT)
            .eq("id", str(sala_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        return SalaListItem.model_validate(
            response.data
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener la sala.",
        )


# ============================================================
# CREAR SALA
# ============================================================


@router.post(
    "",
    response_model=SalaListItem,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {"description": "Datos o relaciones inválidas."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso CREATE_ROOM."},
        409: {
            "description": (
                "Ya existe una sala con el mismo nombre "
                "en el colegio."
            ),
        },
        500: {"description": "Error interno al crear la sala."},
    },
)
async def crear_sala(
    request: Request,
    payload: SalaCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CREATE_ROOM")
    ),
) -> SalaListItem:
    """
    Crea una sala y registra su auditoría en una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        # Se conserva la validación previa para entregar errores claros.
        # PostgreSQL vuelve a validar la relación antes de escribir.
        _obtener_colegio_activo(
            supabase,
            colegio_id=payload.colegio_id,
        )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "crear_sala_atomica",
            {
                "p_colegio_id": str(payload.colegio_id),
                "p_nombre": payload.nombre,
                "p_descripcion": payload.descripcion,
                "p_capacidad": payload.capacidad,
                "p_ubicacion": payload.ubicacion,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de creación de sala devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ROOM_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Ya existe una sala con el mismo nombre "
                        "en el colegio seleccionado."
                    ),
                )

            if error_code in {
                "SCHOOL_NOT_ACTIVE",
                "INVALID_NAME",
                "INVALID_CAPACITY",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos o relaciones de la sala no son válidos.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para crear salas.",
                )

            raise RuntimeError("No fue posible crear la sala.")

        sala_id = resultado.get("sala_id")

        if not sala_id:
            raise RuntimeError("La RPC no devolvió la sala creada.")

        return _obtener_sala_resultado(
            supabase,
            sala_id=UUID(str(sala_id)),
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible crear la sala.",
        )



# ============================================================
# ACTUALIZAR SALA
# ============================================================


@router.patch(
    "/{sala_id}",
    response_model=SalaListItem,
    responses={
        400: {"description": "Datos inválidos o sin cambios."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso UPDATE_ROOM."},
        404: {"description": "Sala no encontrada."},
        409: {
            "description": (
                "Ya existe una sala con el mismo nombre "
                "en el colegio."
            ),
        },
        500: {"description": "Error interno al actualizar la sala."},
    },
)
async def actualizar_sala(
    request: Request,
    sala_id: UUID,
    payload: SalaUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_ROOM")
    ),
) -> SalaListItem:
    """
    Actualiza una sala y su auditoría dentro de una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        cambios = _payload_a_dict(payload)

        if not cambios:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        if "colegio_id" in cambios:
            _obtener_colegio_activo(
                supabase,
                colegio_id=UUID(str(cambios["colegio_id"])),
            )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "actualizar_sala_atomica",
            {
                "p_sala_id": str(sala_id),
                "p_cambios": cambios,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de actualización de sala devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ROOM_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Sala no encontrada.",
                )

            if error_code == "ROOM_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Ya existe una sala con el mismo nombre "
                        "en el colegio seleccionado."
                    ),
                )

            if error_code in {
                "NO_CHANGES",
                "INVALID_FIELDS",
                "INVALID_DATA",
                "INVALID_NAME",
                "INVALID_CAPACITY",
                "SCHOOL_NOT_ACTIVE",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos o relaciones de la sala no son válidos.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para actualizar salas.",
                )

            raise RuntimeError("No fue posible actualizar la sala.")

        return _obtener_sala_resultado(
            supabase,
            sala_id=sala_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar la sala.",
        )



# ============================================================
# ACTIVAR SALA
# ============================================================


@router.patch(
    "/{sala_id}/activate",
    response_model=SalaListItem,
    responses={
        400: {
            "description": (
                "La sala ya está activa o el colegio es inválido."
            ),
        },
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso ACTIVATE_ROOM."},
        404: {"description": "Sala no encontrada."},
        409: {"description": "Existe otra sala con el mismo nombre."},
        500: {"description": "Error interno al activar la sala."},
    },
)
async def activar_sala(
    request: Request,
    sala_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("ACTIVATE_ROOM")
    ),
) -> SalaListItem:
    """
    Activa una sala y registra su auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "activar_sala_atomica",
            {
                "p_sala_id": str(sala_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de activación de sala.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ROOM_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Sala no encontrada.",
                )

            if error_code in {"ALREADY_ACTIVE", "SCHOOL_NOT_ACTIVE"}:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "La sala ya está activa o el colegio "
                        "asociado no se encuentra activo."
                    ),
                )

            if error_code == "ROOM_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Existe otra sala con el mismo nombre.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para activar salas.",
                )

            raise RuntimeError("No fue posible activar la sala.")

        return _obtener_sala_resultado(
            supabase,
            sala_id=sala_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible activar la sala.",
        )



# ============================================================
# DESACTIVAR SALA
# ============================================================


@router.patch(
    "/{sala_id}/deactivate",
    response_model=SalaListItem,
    responses={
        400: {"description": "La sala ya se encuentra inactiva."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso DEACTIVATE_ROOM."},
        404: {"description": "Sala no encontrada."},
        500: {"description": "Error interno al desactivar la sala."},
    },
)
async def desactivar_sala(
    request: Request,
    sala_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("DEACTIVATE_ROOM")
    ),
) -> SalaListItem:
    """
    Desactiva una sala y registra su auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "desactivar_sala_atomica",
            {
                "p_sala_id": str(sala_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de desactivación de sala.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ROOM_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Sala no encontrada.",
                )

            if error_code == "ALREADY_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="La sala ya se encuentra inactiva.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para desactivar salas.",
                )

            raise RuntimeError("No fue posible desactivar la sala.")

        return _obtener_sala_resultado(
            supabase,
            sala_id=sala_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar la sala.",
        )

