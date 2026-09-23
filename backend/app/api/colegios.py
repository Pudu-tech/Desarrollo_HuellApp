"""
Endpoints de administración de colegios en HuellAPP.

Funciones disponibles:
- listar colegios;
- obtener colegio por UUID;
- crear colegio;
- modificar colegio;
- desactivar colegio.

SECURITY:
- Todos los endpoints utilizan permisos RBAC.
- created_by y updated_by provienen del usuario autenticado.
- No se confía en identificadores relacionados sin validarlos.
- Las operaciones sensibles quedan registradas en auditoría.
- No existe eliminación física de colegios desde esta API.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.colegios import (
    ColegioCreate,
    ColegioListItem,
    ColegioUpdate,
)


router = APIRouter(
    prefix="/colegios",
    tags=["Colegios"],
)


# ============================================================
# CAMPOS CONSULTADOS
# ============================================================

COLEGIO_SELECT = """
id,
rbd,
nombre,
descripcion,
tipo_dependencia_id,
direccion,
numero,
complemento,
comuna_id,
region_id,
codigo_postal,
telefono,
email,
sitio_web,
nombre_contacto,
telefono_contacto,
email_contacto,
activo
"""


# ============================================================
# FUNCIONES INTERNAS
# ============================================================


def _request_rpc_context(request: Request) -> dict:
    """
    Construye metadatos comunes para las RPC de escritura.
    """

    request_id_raw = getattr(
        request.state,
        "request_id",
        None,
    )

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


def _obtener_colegio_resultado(
    supabase,
    *,
    colegio_id: UUID,
) -> ColegioListItem:
    """
    Recupera un colegio no eliminado usando el contrato público.
    """

    response = (
        supabase.table("colegios")
        .select(COLEGIO_SELECT)
        .eq("id", str(colegio_id))
        .is_("deleted_at", "null")
        .single()
        .execute()
    )

    return ColegioListItem.model_validate(response.data)






def _payload_a_dict(
    payload: ColegioCreate | ColegioUpdate,
) -> dict:
    """
    Convierte un modelo Pydantic en datos compatibles con Supabase.

    exclude_unset permite que PATCH modifique solamente
    los campos enviados por el cliente.
    """

    return payload.model_dump(
        exclude_unset=True,
        mode="json",
    )


def _validar_relaciones_colegio(
    supabase,
    *,
    region_id: UUID,
    comuna_id: UUID,
    tipo_dependencia_id: UUID | None,
) -> None:
    """
    Valida las relaciones del colegio.

    Reglas:
    - la región debe existir y estar activa;
    - la comuna debe existir y estar activa;
    - la comuna debe pertenecer a la región;
    - el tipo de dependencia, si existe, debe estar activo.
    """

    # --------------------------------------------------------
    # REGIÓN
    # --------------------------------------------------------

    region_response = (
        supabase.table("regiones")
        .select("id,activo")
        .eq("id", str(region_id))
        .maybe_single()
        .execute()
    )

    if (
        not region_response.data
        or region_response.data["activo"] is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La región seleccionada no existe o está inactiva.",
        )

    # --------------------------------------------------------
    # COMUNA
    # --------------------------------------------------------

    comuna_response = (
        supabase.table("comunas")
        .select("id,region_id,activo")
        .eq("id", str(comuna_id))
        .maybe_single()
        .execute()
    )

    if (
        not comuna_response.data
        or comuna_response.data["activo"] is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La comuna seleccionada no existe o está inactiva.",
        )

    # --------------------------------------------------------
    # COHERENCIA COMUNA / REGIÓN
    # --------------------------------------------------------

    if (
        str(comuna_response.data["region_id"])
        != str(region_id)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "La comuna seleccionada no pertenece "
                "a la región indicada."
            ),
        )

    # --------------------------------------------------------
    # TIPO DE DEPENDENCIA
    # --------------------------------------------------------

    if tipo_dependencia_id is not None:
        dependencia_response = (
            supabase.table("tipos_dependencia")
            .select("id,activo")
            .eq("id", str(tipo_dependencia_id))
            .maybe_single()
            .execute()
        )

        if (
            not dependencia_response.data
            or dependencia_response.data["activo"] is not True
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "El tipo de dependencia seleccionado "
                    "no existe o está inactivo."
                ),
            )


# ============================================================
# LISTAR COLEGIOS
# ============================================================


@router.get(
    "",
    response_model=list[ColegioListItem],
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_SCHOOLS.",
        },
        500: {
            "description": "Error interno al obtener colegios.",
        },
    },
)
async def listar_colegios(
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_SCHOOLS")
    ),
) -> list[ColegioListItem]:
    """
    Lista colegios no eliminados lógicamente.

    Se incluyen colegios activos e inactivos para permitir
    su administración y trazabilidad.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .is_("deleted_at", "null")
            .order("nombre")
            .execute()
        )

        return [
            ColegioListItem.model_validate(item)
            for item in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener los colegios.",
        )


# ============================================================
# OBTENER COLEGIO
# ============================================================


@router.get(
    "/{colegio_id}",
    response_model=ColegioListItem,
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_SCHOOLS.",
        },
        404: {
            "description": "Colegio no encontrado.",
        },
        500: {
            "description": "Error interno al obtener el colegio.",
        },
    },
)
async def obtener_colegio(
    colegio_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_SCHOOLS")
    ),
) -> ColegioListItem:
    """
    Obtiene un colegio no eliminado lógicamente por UUID.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT)
            .eq("id", str(colegio_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        return ColegioListItem.model_validate(
            response.data
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener el colegio.",
        )


# ============================================================
# CREAR COLEGIO
# ============================================================


@router.post(
    "",
    response_model=ColegioListItem,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {"description": "Datos o relaciones inválidas."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso CREATE_SCHOOL."},
        409: {"description": "El RBD ya se encuentra registrado."},
        500: {"description": "Error interno al crear el colegio."},
    },
)
async def crear_colegio(
    request: Request,
    payload: ColegioCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CREATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Crea un colegio y su auditoría dentro de una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        # Mantiene las validaciones funcionales antes de abrir la escritura.
        _validar_relaciones_colegio(
            supabase,
            region_id=payload.region_id,
            comuna_id=payload.comuna_id,
            tipo_dependencia_id=payload.tipo_dependencia_id,
        )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "crear_colegio_atomico",
            {
                "p_datos": _payload_a_dict(payload),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de creación de colegio devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "RBD_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El RBD ya se encuentra registrado.",
                )

            if error_code in {
                "REGION_NOT_FOUND",
                "COMUNA_NOT_FOUND_OR_MISMATCH",
                "DEPENDENCY_TYPE_NOT_FOUND",
                "INVALID_DATA",
                "INVALID_RELATION_ID",
                "INVALID_REQUIRED_FIELD",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos o relaciones del colegio no son válidos.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para crear colegios.",
                )

            raise RuntimeError("No fue posible crear el colegio.")

        colegio_id = resultado.get("colegio_id")

        if not colegio_id:
            raise RuntimeError("La RPC no devolvió el colegio creado.")

        return _obtener_colegio_resultado(
            supabase,
            colegio_id=UUID(str(colegio_id)),
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible crear el colegio.",
        )



# ============================================================
# ACTUALIZAR COLEGIO
# ============================================================


@router.patch(
    "/{colegio_id}",
    response_model=ColegioListItem,
    responses={
        400: {"description": "Datos inválidos o sin cambios."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso UPDATE_SCHOOL."},
        404: {"description": "Colegio no encontrado."},
        409: {"description": "El RBD ya se encuentra registrado."},
        500: {"description": "Error interno al actualizar el colegio."},
    },
)
async def actualizar_colegio(
    request: Request,
    colegio_id: UUID,
    payload: ColegioUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Actualiza un colegio y su auditoría dentro de una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        current_response = (
            supabase.table("colegios")
            .select(COLEGIO_SELECT + ",deleted_at")
            .eq("id", str(colegio_id))
            .maybe_single()
            .execute()
        )

        if (
            not current_response.data
            or current_response.data.get("deleted_at") is not None
        ):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Colegio no encontrado.",
            )

        colegio_actual = ColegioListItem.model_validate(
            current_response.data
        )

        cambios = _payload_a_dict(payload)

        if not cambios:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        campos_relacionados = {
            "region_id",
            "comuna_id",
            "tipo_dependencia_id",
        }

        if campos_relacionados.intersection(cambios):
            region_final = UUID(
                str(cambios.get("region_id", colegio_actual.region_id))
            )
            comuna_final = UUID(
                str(cambios.get("comuna_id", colegio_actual.comuna_id))
            )
            dependencia_raw = cambios.get(
                "tipo_dependencia_id",
                colegio_actual.tipo_dependencia_id,
            )
            dependencia_final = (
                UUID(str(dependencia_raw))
                if dependencia_raw is not None
                else None
            )

            _validar_relaciones_colegio(
                supabase,
                region_id=region_final,
                comuna_id=comuna_final,
                tipo_dependencia_id=dependencia_final,
            )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "actualizar_colegio_atomico",
            {
                "p_colegio_id": str(colegio_id),
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
                "La RPC de actualización de colegio devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "SCHOOL_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Colegio no encontrado.",
                )

            if error_code == "RBD_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El RBD ya se encuentra registrado.",
                )

            if error_code in {
                "NO_CHANGES",
                "INVALID_FIELDS",
                "INVALID_REQUIRED_FIELD",
                "INVALID_RELATION_ID",
                "REGION_NOT_FOUND",
                "COMUNA_NOT_FOUND_OR_MISMATCH",
                "DEPENDENCY_TYPE_NOT_FOUND",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos o relaciones del colegio no son válidos.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para actualizar colegios.",
                )

            raise RuntimeError("No fue posible actualizar el colegio.")

        return _obtener_colegio_resultado(
            supabase,
            colegio_id=colegio_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar el colegio.",
        )


# ============================================================
# ACTIVAR COLEGIO
# ============================================================


@router.patch(
    "/{colegio_id}/activate",
    response_model=ColegioListItem,
    responses={
        400: {"description": "El colegio ya se encuentra activo."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso ACTIVATE_SCHOOL."},
        404: {"description": "Colegio no encontrado."},
        500: {"description": "Error interno al activar el colegio."},
    },
)
async def activar_colegio(
    request: Request,
    colegio_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("ACTIVATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Activa un colegio y registra auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "activar_colegio_atomico",
            {
                "p_colegio_id": str(colegio_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de activación de colegio.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "SCHOOL_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Colegio no encontrado.",
                )

            if error_code == "ALREADY_ACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El colegio ya se encuentra activo.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para activar colegios.",
                )

            raise RuntimeError("No fue posible activar el colegio.")

        return _obtener_colegio_resultado(
            supabase,
            colegio_id=colegio_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible activar el colegio.",
        )





# ============================================================
# DESACTIVAR COLEGIO
# ============================================================


@router.patch(
    "/{colegio_id}/deactivate",
    response_model=ColegioListItem,
    responses={
        400: {"description": "El colegio ya se encuentra inactivo."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso DEACTIVATE_SCHOOL."},
        404: {"description": "Colegio no encontrado."},
        500: {"description": "Error interno al desactivar el colegio."},
    },
)
async def desactivar_colegio(
    request: Request,
    colegio_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("DEACTIVATE_SCHOOL")
    ),
) -> ColegioListItem:
    """
    Desactiva un colegio y registra auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "desactivar_colegio_atomico",
            {
                "p_colegio_id": str(colegio_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de desactivación de colegio.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "SCHOOL_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Colegio no encontrado.",
                )

            if error_code == "ALREADY_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El colegio ya se encuentra inactivo.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para desactivar colegios.",
                )

            raise RuntimeError("No fue posible desactivar el colegio.")

        return _obtener_colegio_resultado(
            supabase,
            colegio_id=colegio_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar el colegio.",
        )

