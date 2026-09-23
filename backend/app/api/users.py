"""
Endpoints relacionados con la administración de usuarios en HuellAPP.

Este módulo contiene los endpoints del mantenedor de usuarios.

SECURITY:
- Todos los endpoints sensibles requieren permisos explícitos.
- La autorización se valida en FastAPI.
- No se confía en roles o permisos enviados por el frontend.
- No se exponen contraseñas, tokens ni secretos.
- Los usuarios eliminados lógicamente no se consideran visibles.
- Las operaciones sensibles quedan registradas en auditoría.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.users import (
    UserCreate,
    UserCreateResponse,
    UserListItem,
    UserRoleUpdate,
    UserUpdate,
)


router = APIRouter(
    prefix="/users",
    tags=["Users"],
)


def _request_rpc_context(request: Request) -> dict:
    """
    Construye metadatos comunes enviados a las RPC de escritura.

    El actor nunca se obtiene desde el frontend; únicamente se propagan
    identificadores y metadatos de la solicitud autenticada actual.
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


def _get_user_result(
    supabase,
    *,
    user_id: UUID,
) -> UserListItem:
    """
    Recupera el contrato público de un usuario no eliminado.
    """

    response = (
        supabase.table("usuarios")
        .select(
            """
            id,
            rut,
            nombres,
            apellido_paterno,
            apellido_materno,
            email,
            telefono,
            activo,
            roles(
                codigo,
                nombre
            )
            """
        )
        .eq("id", str(user_id))
        .is_("deleted_at", "null")
        .single()
        .execute()
    )

    return UserListItem.model_validate(response.data)


# ============================================================
# CONSULTAS
# ============================================================


@router.get(
    "",
    response_model=list[UserListItem],
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "El usuario no posee el permiso VIEW_USERS.",
        },
        500: {
            "description": "Error interno al obtener el listado de usuarios.",
        },
    },
)
async def list_users(
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_USERS")
    ),
) -> list[UserListItem]:
    """
    Lista los usuarios no eliminados lógicamente del sistema.

    Requiere:
        VIEW_USERS
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                rut,
                nombres,
                apellido_paterno,
                apellido_materno,
                email,
                telefono,
                activo,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .is_("deleted_at", "null")
            .order("apellido_paterno")
            .order("nombres")
            .execute()
        )

        return [
            UserListItem.model_validate(user)
            for user in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener el listado de usuarios.",
        )


@router.get(
    "/{user_id}",
    response_model=UserListItem,
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "El usuario no posee el permiso VIEW_USERS.",
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": "Error interno al obtener el usuario.",
        },
    },
)
async def get_user_by_id(
    user_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_USERS")
    ),
) -> UserListItem:
    """
    Obtiene un usuario por UUID.

    Requiere:
        VIEW_USERS
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                rut,
                nombres,
                apellido_paterno,
                apellido_materno,
                email,
                telefono,
                activo,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq("id", str(user_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        return UserListItem.model_validate(response.data)

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener el usuario.",
        )


# ============================================================
# CREACIÓN
# ============================================================


@router.post(
    "",
    response_model=UserCreateResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {
            "description": "Datos inválidos o rol no permitido.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "El usuario no posee permiso para crear usuarios.",
        },
        409: {
            "description": "El RUT o correo ya se encuentra registrado.",
        },
        500: {
            "description": "Error interno al crear el usuario.",
        },
    },
)
async def create_user(
    request: Request,
    payload: UserCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CREATE_USER")
    ),
) -> UserCreateResponse:
    """
    Crea un usuario mediante un flujo híbrido seguro.

    Supabase Auth y PostgreSQL no comparten una transacción ACID.

    Flujo:
    - valida reglas funcionales antes de crear la identidad;
    - crea la identidad en Supabase Auth;
    - crea public.usuarios + audit_logs mediante una RPC PostgreSQL atómica;
    - si PostgreSQL falla antes de confirmar el perfil, elimina
      compensatoriamente la identidad recién creada en Auth.

    La contraseña nunca se envía a PostgreSQL ni se registra en auditoría.
    """

    supabase = get_supabase_client()

    auth_user_id: str | None = None
    db_creation_committed = False

    try:
        # --------------------------------------------------------
        # 1. Validar rol solicitado antes de crear la identidad.
        #    La RPC repite esta regla como defensa en profundidad.
        # --------------------------------------------------------
        role_response = (
            supabase.table("roles")
            .select("id,codigo,nombre")
            .eq("codigo", payload.role_code)
            .eq("activo", True)
            .maybe_single()
            .execute()
        )

        if not role_response.data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El rol solicitado no existe o está inactivo.",
            )

        requested_role = role_response.data

        if (
            current_user.role_code == "DIRECTIVA"
            and requested_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede crear usuarios SUPERADMIN.",
            )

        # --------------------------------------------------------
        # 2. Prevalidar duplicados para responder antes de tocar Auth.
        #    PostgreSQL vuelve a validarlos de forma autoritativa.
        # --------------------------------------------------------
        rut_response = (
            supabase.table("usuarios")
            .select("id")
            .eq("rut", payload.rut)
            .limit(1)
            .execute()
        )

        if rut_response.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El RUT ya se encuentra registrado.",
            )

        email_response = (
            supabase.table("usuarios")
            .select("id")
            .ilike("email", str(payload.email))
            .limit(1)
            .execute()
        )

        if email_response.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El correo ya se encuentra registrado.",
            )

        # --------------------------------------------------------
        # 3. Crear identidad en Supabase Auth.
        # --------------------------------------------------------
        auth_response = supabase.auth.admin.create_user(
            {
                "email": str(payload.email),
                "password": payload.password,
                "email_confirm": True,
            }
        )

        if not auth_response.user:
            raise RuntimeError(
                "No fue posible crear la identidad en Supabase Auth."
            )

        auth_user_id = str(auth_response.user.id)

        # --------------------------------------------------------
        # 4. Crear perfil + auditoría en una sola transacción SQL.
        # --------------------------------------------------------
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "crear_usuario_atomico",
            {
                "p_user_id": auth_user_id,
                "p_rut": payload.rut,
                "p_nombres": payload.nombres,
                "p_apellido_paterno": payload.apellido_paterno,
                "p_apellido_materno": payload.apellido_materno,
                "p_email": str(payload.email),
                "p_telefono": payload.telefono,
                "p_role_code": payload.role_code,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de creación de usuario devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code in {
                "RUT_EXISTS",
                "EMAIL_EXISTS",
                "USER_ID_EXISTS",
                "DUPLICATE_USER",
            }:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El RUT o correo ya se encuentra registrado.",
                )

            if error_code == "ROLE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El rol solicitado no existe o está inactivo.",
                )

            if error_code in {
                "INVALID_USER_ID",
                "INVALID_RUT",
                "INVALID_NAME",
                "INVALID_EMAIL",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos enviados para crear el usuario no son válidos.",
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No autorizado para crear este usuario.",
                )

            raise RuntimeError(
                "La RPC no pudo completar la creación del usuario."
            )

        db_creation_committed = True

        usuario = resultado.get("usuario")

        if not isinstance(usuario, dict):
            raise RuntimeError(
                "La RPC no devolvió el usuario creado."
            )

        return UserCreateResponse.model_validate(usuario)

    except HTTPException:
        # Si Auth ya creó la identidad pero PostgreSQL no confirmó el perfil,
        # se compensa eliminando únicamente esa identidad recién creada.
        if auth_user_id is not None and not db_creation_committed:
            try:
                supabase.auth.admin.delete_user(auth_user_id)
            except Exception:
                pass

        raise

    except Exception:
        if auth_user_id is not None and not db_creation_committed:
            try:
                supabase.auth.admin.delete_user(auth_user_id)
            except Exception:
                pass

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible crear el usuario.",
        )



# ============================================================
# EDICIÓN DE DATOS BÁSICOS
# ============================================================


@router.patch(
    "/{user_id}",
    response_model=UserListItem,
    responses={
        400: {"description": "No se enviaron campos válidos para actualizar."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No autorizado para modificar este usuario."},
        404: {"description": "Usuario no encontrado."},
        500: {"description": "Error interno al actualizar el usuario."},
    },
)
async def update_user(
    request: Request,
    user_id: UUID,
    payload: UserUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_USER")
    ),
) -> UserListItem:
    """
    Actualiza datos básicos y auditoría dentro de una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        cambios = payload.model_dump(exclude_unset=True)

        if not cambios:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "actualizar_usuario_atomico",
            {
                "p_user_id": str(user_id),
                "p_cambios": cambios,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de actualización de usuario.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Usuario no encontrado.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN", "FORBIDDEN_SUPERADMIN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No autorizado para modificar este usuario.",
                )

            if error_code in {"NO_CHANGES", "INVALID_FIELDS", "INVALID_REQUIRED_FIELD"}:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos enviados para actualizar no son válidos.",
                )

            raise RuntimeError("No fue posible actualizar el usuario.")

        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar el usuario.",
        )



# ============================================================
# CAMBIO DE ROL
# ============================================================


@router.patch(
    "/{user_id}/role",
    response_model=UserListItem,
    responses={
        400: {"description": "Rol solicitado inválido."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No autorizado para cambiar el rol."},
        404: {"description": "Usuario o rol no encontrado."},
        500: {"description": "Error interno al cambiar el rol."},
    },
)
async def update_user_role(
    request: Request,
    user_id: UUID,
    payload: UserRoleUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CHANGE_USER_ROLE")
    ),
) -> UserListItem:
    """
    Cambia el rol y registra auditoría dentro de una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "cambiar_rol_usuario_atomico",
            {
                "p_user_id": str(user_id),
                "p_role_code": payload.role_code,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de cambio de rol.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Usuario no encontrado.",
                )

            if error_code == "ROLE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="El rol solicitado no existe o está inactivo.",
                )

            if error_code == "SAME_ROLE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El usuario ya posee el rol solicitado.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN", "FORBIDDEN_SUPERADMIN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No autorizado para cambiar el rol.",
                )

            raise RuntimeError("No fue posible cambiar el rol.")

        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible cambiar el rol del usuario.",
        )



# ============================================================
# ACTIVACIÓN
# ============================================================


@router.patch(
    "/{user_id}/activate",
    response_model=UserListItem,
    responses={
        400: {"description": "El usuario ya se encuentra activo."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No autorizado para activar este usuario."},
        404: {"description": "Usuario no encontrado."},
        500: {"description": "Error interno al activar el usuario."},
    },
)
async def activate_user(
    request: Request,
    user_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("ACTIVATE_USER")
    ),
) -> UserListItem:
    """
    Activa un usuario y registra auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "activar_usuario_atomico",
            {
                "p_user_id": str(user_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de activación de usuario.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Usuario no encontrado.",
                )

            if error_code == "ALREADY_ACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El usuario ya se encuentra activo.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN", "FORBIDDEN_SUPERADMIN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No autorizado para activar este usuario.",
                )

            raise RuntimeError("No fue posible activar el usuario.")

        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible activar el usuario.",
        )



# ============================================================
# DESACTIVACIÓN
# ============================================================


@router.patch(
    "/{user_id}/deactivate",
    response_model=UserListItem,
    responses={
        400: {"description": "El usuario ya se encuentra inactivo."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No autorizado para desactivar este usuario."},
        404: {"description": "Usuario no encontrado."},
        500: {"description": "Error interno al desactivar el usuario."},
    },
)
async def deactivate_user(
    request: Request,
    user_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("DEACTIVATE_USER")
    ),
) -> UserListItem:
    """
    Desactiva un usuario y registra auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "desactivar_usuario_atomico",
            {
                "p_user_id": str(user_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de desactivación de usuario.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Usuario no encontrado.",
                )

            if error_code == "ALREADY_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El usuario ya se encuentra inactivo.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN", "FORBIDDEN_SUPERADMIN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No autorizado para desactivar este usuario.",
                )

            raise RuntimeError("No fue posible desactivar el usuario.")

        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar el usuario.",
        )



# ============================================================
# BORRADO LÓGICO
# ============================================================


@router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        400: {"description": "Operación no permitida."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No autorizado para eliminar este usuario."},
        404: {"description": "Usuario no encontrado."},
        500: {"description": "Error interno al eliminar el usuario."},
    },
)
async def delete_user(
    request: Request,
    user_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("DELETE_USER")
    ),
) -> None:
    """
    Realiza borrado lógico y auditoría dentro de una sola transacción.

    La identidad de Supabase Auth se conserva.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "eliminar_usuario_atomico",
            {
                "p_user_id": str(user_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de borrado lógico.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Usuario no encontrado.",
                )

            if error_code == "SELF_DELETE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="No puede eliminar su propio usuario.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN", "FORBIDDEN_SUPERADMIN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No autorizado para eliminar este usuario.",
                )

            raise RuntimeError("No fue posible realizar el borrado lógico.")

        return None

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible eliminar el usuario.",
        )

