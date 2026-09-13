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
from app.services.audit import write_audit_log


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


def _sala_a_auditoria(
    sala: SalaListItem,
) -> dict:
    """
    Convierte una sala a un diccionario serializable para auditoría.
    """

    return {
        "id": str(sala.id),
        "colegio_id": str(sala.colegio_id),
        "nombre": sala.nombre,
        "descripcion": sala.descripcion,
        "capacidad": sala.capacidad,
        "ubicacion": sala.ubicacion,
        "activo": sala.activo,
        "created_at": sala.created_at.isoformat(),
        "updated_at": sala.updated_at.isoformat(),
    }


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


def _validar_duplicado_sala(
    supabase,
    *,
    colegio_id: UUID,
    nombre: str,
    sala_id_excluir: UUID | None = None,
) -> None:
    """
    Valida la unicidad lógica de una sala por:

        colegio_id + nombre

    La base también posee la constraint:
        uq_sala_colegio_nombre

    Esta validación entrega un mensaje HTTP más claro.
    """

    query = (
        supabase.table("salas")
        .select("id")
        .eq("colegio_id", str(colegio_id))
        .eq("nombre", nombre)
        .is_("deleted_at", "null")
    )

    if sala_id_excluir is not None:
        query = query.neq(
            "id",
            str(sala_id_excluir),
        )

    response = (
        query
        .limit(1)
        .execute()
    )

    if response.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Ya existe una sala con el mismo nombre "
                "en el colegio seleccionado."
            ),
        )


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
        400: {
            "description": "Datos o relaciones inválidas.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso CREATE_ROOM.",
        },
        409: {
            "description": (
                "Ya existe una sala con el mismo nombre "
                "en el colegio."
            ),
        },
        500: {
            "description": "Error interno al crear la sala.",
        },
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
    Crea una sala asociada a un colegio.

    Reglas:
    - el colegio debe existir y estar activo;
    - no puede existir otra sala con el mismo nombre
      dentro del mismo colegio.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. VALIDAR COLEGIO
        # --------------------------------------------------------

        _obtener_colegio_activo(
            supabase,
            colegio_id=payload.colegio_id,
        )

        # --------------------------------------------------------
        # 2. VALIDAR DUPLICADO
        # --------------------------------------------------------

        _validar_duplicado_sala(
            supabase,
            colegio_id=payload.colegio_id,
            nombre=payload.nombre,
        )

        # --------------------------------------------------------
        # 3. CREAR SALA
        # --------------------------------------------------------

        insert_data = _payload_a_dict(payload)

        insert_data["activo"] = True
        insert_data["created_by"] = str(current_user.id)
        insert_data["updated_by"] = str(current_user.id)

        insert_response = (
            supabase.table("salas")
            .insert(insert_data)
            .execute()
        )

        if not insert_response.data:
            raise RuntimeError(
                "No se creó la sala."
            )

        sala_id = insert_response.data[0]["id"]

        # --------------------------------------------------------
        # 4. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        created_response = (
            supabase.table("salas")
            .select(SALA_SELECT)
            .eq("id", sala_id)
            .single()
            .execute()
        )

        sala = SalaListItem.model_validate(
            created_response.data
        )

        # --------------------------------------------------------
        # 5. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="CREATE_ROOM",
            entity_type="ROOM",
            entity_id=sala.id,
            old_values=None,
            new_values=_sala_a_auditoria(sala),
            description="Creación de sala.",
        )

        return sala

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
        400: {
            "description": "Datos inválidos o sin cambios.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso UPDATE_ROOM.",
        },
        404: {
            "description": "Sala no encontrada.",
        },
        409: {
            "description": (
                "Ya existe una sala con el mismo nombre "
                "en el colegio."
            ),
        },
        500: {
            "description": "Error interno al actualizar la sala.",
        },
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
    Modifica parcialmente una sala existente.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER ESTADO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("salas")
            .select(SALA_SELECT + ",deleted_at")
            .eq("id", str(sala_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        sala_actual = SalaListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. OBTENER CAMPOS ENVIADOS
        # --------------------------------------------------------

        update_data = _payload_a_dict(payload)

        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        # --------------------------------------------------------
        # 3. CALCULAR ESTADO FINAL
        # --------------------------------------------------------

        colegio_final = UUID(
            str(
                update_data.get(
                    "colegio_id",
                    sala_actual.colegio_id,
                )
            )
        )

        nombre_final = update_data.get(
            "nombre",
            sala_actual.nombre,
        )

        # --------------------------------------------------------
        # 4. VALIDAR COLEGIO SOLO SI CAMBIA
        # --------------------------------------------------------

        if "colegio_id" in update_data:
            _obtener_colegio_activo(
                supabase,
                colegio_id=colegio_final,
            )

        # --------------------------------------------------------
        # 5. VALIDAR DUPLICADO FINAL
        # --------------------------------------------------------

        _validar_duplicado_sala(
            supabase,
            colegio_id=colegio_final,
            nombre=nombre_final,
            sala_id_excluir=sala_id,
        )

        # --------------------------------------------------------
        # 6. ACTUALIZAR
        # --------------------------------------------------------

        update_data["updated_by"] = str(current_user.id)

        update_response = (
            supabase.table("salas")
            .update(update_data)
            .eq("id", str(sala_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible actualizar la sala."
            )

        # --------------------------------------------------------
        # 7. CONSULTAR ESTADO POSTERIOR
        # --------------------------------------------------------

        updated_response = (
            supabase.table("salas")
            .select(SALA_SELECT)
            .eq("id", str(sala_id))
            .single()
            .execute()
        )

        sala_actualizada = SalaListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 8. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="UPDATE_ROOM",
            entity_type="ROOM",
            entity_id=sala_actualizada.id,
            old_values=_sala_a_auditoria(
                sala_actual
            ),
            new_values=_sala_a_auditoria(
                sala_actualizada
            ),
            description="Actualización de sala.",
        )

        return sala_actualizada

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
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso ACTIVATE_ROOM.",
        },
        404: {
            "description": "Sala no encontrada.",
        },
        409: {
            "description": (
                "Existe otra sala con el mismo nombre."
            ),
        },
        500: {
            "description": "Error interno al activar la sala.",
        },
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
    Reactiva una sala previamente desactivada.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER SALA ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("salas")
            .select(SALA_SELECT + ",deleted_at")
            .eq("id", str(sala_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        sala_actual = SalaListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. VALIDAR ESTADO
        # --------------------------------------------------------

        if sala_actual.activo is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La sala ya se encuentra activa.",
            )

        # --------------------------------------------------------
        # 3. VALIDAR COLEGIO
        # --------------------------------------------------------

        _obtener_colegio_activo(
            supabase,
            colegio_id=sala_actual.colegio_id,
        )

        # --------------------------------------------------------
        # 4. VALIDAR DUPLICADO
        # --------------------------------------------------------

        _validar_duplicado_sala(
            supabase,
            colegio_id=sala_actual.colegio_id,
            nombre=sala_actual.nombre,
            sala_id_excluir=sala_id,
        )

        # --------------------------------------------------------
        # 5. ACTIVAR
        # --------------------------------------------------------

        update_response = (
            supabase.table("salas")
            .update(
                {
                    "activo": True,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(sala_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible activar la sala."
            )

        # --------------------------------------------------------
        # 6. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        updated_response = (
            supabase.table("salas")
            .select(SALA_SELECT)
            .eq("id", str(sala_id))
            .single()
            .execute()
        )

        sala_actualizada = SalaListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 7. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="ACTIVATE_ROOM",
            entity_type="ROOM",
            entity_id=sala_actualizada.id,
            old_values={
                "activo": False,
            },
            new_values={
                "activo": True,
            },
            description="Activación de sala.",
        )

        return sala_actualizada

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
        400: {
            "description": "La sala ya se encuentra inactiva.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso DEACTIVATE_ROOM.",
        },
        404: {
            "description": "Sala no encontrada.",
        },
        500: {
            "description": "Error interno al desactivar la sala.",
        },
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
    Desactiva una sala.

    La operación no elimina físicamente el registro.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER SALA ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("salas")
            .select(SALA_SELECT + ",deleted_at")
            .eq("id", str(sala_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Sala no encontrada.",
            )

        sala_actual = SalaListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. VALIDAR ESTADO
        # --------------------------------------------------------

        if sala_actual.activo is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La sala ya se encuentra inactiva.",
            )

        # --------------------------------------------------------
        # 3. DESACTIVAR
        # --------------------------------------------------------

        update_response = (
            supabase.table("salas")
            .update(
                {
                    "activo": False,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(sala_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible desactivar la sala."
            )

        # --------------------------------------------------------
        # 4. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        updated_response = (
            supabase.table("salas")
            .select(SALA_SELECT)
            .eq("id", str(sala_id))
            .single()
            .execute()
        )

        sala_actualizada = SalaListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 5. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="DEACTIVATE_ROOM",
            entity_type="ROOM",
            entity_id=sala_actualizada.id,
            old_values={
                "activo": True,
            },
            new_values={
                "activo": False,
            },
            description="Desactivación de sala.",
        )

        return sala_actualizada

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar la sala.",
        )