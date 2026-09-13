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

from datetime import datetime, timezone
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
from app.services.audit import write_audit_log


router = APIRouter(
    prefix="/users",
    tags=["Users"],
)


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
    Crea un usuario en Supabase Auth y public.usuarios.

    Reglas:
        - SUPERADMIN puede crear cualquier rol.
        - DIRECTIVA no puede crear SUPERADMIN.
        - RUT y correo deben ser únicos.
    """

    supabase = get_supabase_client()

    auth_user_id: str | None = None
    profile_created = False

    try:
        # --------------------------------------------------------
        # 1. Validar rol solicitado.
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

        # DIRECTIVA nunca puede crear SUPERADMIN.
        if (
            current_user.role_code == "DIRECTIVA"
            and requested_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede crear usuarios SUPERADMIN.",
            )

        # --------------------------------------------------------
        # 2. Validar RUT duplicado.
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

        # --------------------------------------------------------
        # 3. Validar correo duplicado.
        # --------------------------------------------------------
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
        # 4. Crear identidad en Supabase Auth.
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
        # 5. Crear perfil en public.usuarios.
        # --------------------------------------------------------
        profile_response = (
            supabase.table("usuarios")
            .insert(
                {
                    "id": auth_user_id,
                    "rut": payload.rut,
                    "nombres": payload.nombres,
                    "apellido_paterno": payload.apellido_paterno,
                    "apellido_materno": payload.apellido_materno,
                    "email": str(payload.email),
                    "telefono": payload.telefono,
                    "rol_id": requested_role["id"],
                    "activo": True,
                    "created_by": str(current_user.id),
                    "updated_by": str(current_user.id),
                }
            )
            .execute()
        )

        if not profile_response.data:
            raise RuntimeError(
                "No se creó el perfil en public.usuarios."
            )

        profile_created = True

        # --------------------------------------------------------
        # 6. Consultar resultado final.
        # --------------------------------------------------------
        created_response = (
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
            .eq("id", auth_user_id)
            .single()
            .execute()
        )

        created_user = UserCreateResponse.model_validate(
            created_response.data
        )

        # --------------------------------------------------------
        # 7. Auditoría.
        #
        # SECURITY:
        # Nunca se registra la contraseña.
        # --------------------------------------------------------
        await write_audit_log(
            request=request,
            actor=current_user,
            action="CREATE_USER",
            entity_type="USER",
            entity_id=created_user.id,
            old_values=None,
            new_values={
                "id": str(created_user.id),
                "rut": created_user.rut,
                "nombres": created_user.nombres,
                "apellido_paterno": created_user.apellido_paterno,
                "apellido_materno": created_user.apellido_materno,
                "email": str(created_user.email),
                "telefono": created_user.telefono,
                "activo": created_user.activo,
                "role_code": created_user.roles.codigo,
            },
            description="Creación de usuario.",
        )

        return created_user

    except HTTPException:
        raise

    except Exception:
        # Rollback compensatorio de creación.
        if auth_user_id is not None:
            if profile_created:
                try:
                    (
                        supabase.table("usuarios")
                        .delete()
                        .eq("id", auth_user_id)
                        .execute()
                    )
                except Exception:
                    pass

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
        400: {
            "description": "No se enviaron campos válidos para actualizar.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No autorizado para modificar este usuario.",
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": "Error interno al actualizar el usuario.",
        },
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
    Actualiza datos básicos del usuario.

    No modifica:
        - rol
        - correo
        - contraseña
        - estado
    """

    supabase = get_supabase_client()

    try:
        target_response = (
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
                deleted_at,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq("id", str(user_id))
            .maybe_single()
            .execute()
        )

        if not target_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_user = target_response.data

        if target_user.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_role = target_user.get("roles")

        if not target_role:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="No fue posible determinar el rol del usuario.",
            )

        if (
            current_user.role_code == "DIRECTIVA"
            and target_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede modificar usuarios SUPERADMIN.",
            )

        update_data = payload.model_dump(exclude_unset=True)

        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        update_data["updated_by"] = str(current_user.id)

        update_response = (
            supabase.table("usuarios")
            .update(update_data)
            .eq("id", str(user_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible actualizar el usuario."
            )

        updated_response = (
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
            .single()
            .execute()
        )

        updated_user = UserListItem.model_validate(
            updated_response.data
        )

        await write_audit_log(
            request=request,
            actor=current_user,
            action="UPDATE_USER",
            entity_type="USER",
            entity_id=updated_user.id,
            old_values={
                "rut": target_user.get("rut"),
                "nombres": target_user.get("nombres"),
                "apellido_paterno": target_user.get(
                    "apellido_paterno"
                ),
                "apellido_materno": target_user.get(
                    "apellido_materno"
                ),
                "email": target_user.get("email"),
                "telefono": target_user.get("telefono"),
                "activo": target_user.get("activo"),
                "role_code": target_role.get("codigo"),
            },
            new_values={
                "rut": updated_user.rut,
                "nombres": updated_user.nombres,
                "apellido_paterno": updated_user.apellido_paterno,
                "apellido_materno": updated_user.apellido_materno,
                "email": str(updated_user.email),
                "telefono": updated_user.telefono,
                "activo": updated_user.activo,
                "role_code": updated_user.roles.codigo,
            },
            description="Actualización de datos de usuario.",
        )

        return updated_user

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
        400: {
            "description": "Rol solicitado inválido.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No autorizado para cambiar el rol.",
        },
        404: {
            "description": "Usuario o rol no encontrado.",
        },
        500: {
            "description": "Error interno al cambiar el rol.",
        },
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
    Cambia el rol de un usuario.

    Reglas:
        - SUPERADMIN puede asignar cualquier rol.
        - DIRECTIVA no puede administrar ni asignar SUPERADMIN.
    """

    supabase = get_supabase_client()

    try:
        target_response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                deleted_at,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq("id", str(user_id))
            .maybe_single()
            .execute()
        )

        if not target_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_user = target_response.data

        if target_user.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_role = target_user.get("roles")

        if not target_role:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="No fue posible determinar el rol actual.",
            )

        if (
            current_user.role_code == "DIRECTIVA"
            and target_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede modificar usuarios SUPERADMIN.",
            )

        new_role_response = (
            supabase.table("roles")
            .select("id,codigo,nombre")
            .eq("codigo", payload.role_code)
            .eq("activo", True)
            .maybe_single()
            .execute()
        )

        if not new_role_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="El rol solicitado no existe o está inactivo.",
            )

        new_role = new_role_response.data

        if (
            current_user.role_code == "DIRECTIVA"
            and new_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede asignar el rol SUPERADMIN.",
            )

        if target_role["codigo"] == new_role["codigo"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El usuario ya posee el rol solicitado.",
            )

        update_response = (
            supabase.table("usuarios")
            .update(
                {
                    "rol_id": new_role["id"],
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(user_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible cambiar el rol."
            )

        updated_response = (
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
            .single()
            .execute()
        )

        updated_user = UserListItem.model_validate(
            updated_response.data
        )

        await write_audit_log(
            request=request,
            actor=current_user,
            action="CHANGE_USER_ROLE",
            entity_type="USER",
            entity_id=updated_user.id,
            old_values={
                "role_code": target_role["codigo"],
            },
            new_values={
                "role_code": updated_user.roles.codigo,
            },
            description="Cambio de rol de usuario.",
        )

        return updated_user

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
        400: {
            "description": "El usuario ya se encuentra activo.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No autorizado para activar este usuario.",
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": "Error interno al activar el usuario.",
        },
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
    Activa un usuario existente.
    """

    supabase = get_supabase_client()

    try:
        target_response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                activo,
                deleted_at,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq("id", str(user_id))
            .maybe_single()
            .execute()
        )

        if not target_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_user = target_response.data

        if target_user.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_role = target_user.get("roles")

        if not target_role:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="No fue posible determinar el rol.",
            )

        if (
            current_user.role_code == "DIRECTIVA"
            and target_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede administrar usuarios SUPERADMIN.",
            )

        if target_user["activo"] is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El usuario ya se encuentra activo.",
            )

        update_response = (
            supabase.table("usuarios")
            .update(
                {
                    "activo": True,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(user_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible activar el usuario."
            )

        updated_response = (
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
            .single()
            .execute()
        )

        updated_user = UserListItem.model_validate(
            updated_response.data
        )

        await write_audit_log(
            request=request,
            actor=current_user,
            action="ACTIVATE_USER",
            entity_type="USER",
            entity_id=updated_user.id,
            old_values={
                "activo": False,
            },
            new_values={
                "activo": True,
            },
            description="Activación de usuario.",
        )

        return updated_user

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
        400: {
            "description": "El usuario ya se encuentra inactivo.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No autorizado para desactivar este usuario.",
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": "Error interno al desactivar el usuario.",
        },
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
    Desactiva un usuario existente.
    """

    supabase = get_supabase_client()

    try:
        target_response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                activo,
                deleted_at,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq("id", str(user_id))
            .maybe_single()
            .execute()
        )

        if not target_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_user = target_response.data

        if target_user.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_role = target_user.get("roles")

        if not target_role:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="No fue posible determinar el rol.",
            )

        if (
            current_user.role_code == "DIRECTIVA"
            and target_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede administrar usuarios SUPERADMIN.",
            )

        if target_user["activo"] is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El usuario ya se encuentra inactivo.",
            )

        update_response = (
            supabase.table("usuarios")
            .update(
                {
                    "activo": False,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(user_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible desactivar el usuario."
            )

        updated_response = (
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
            .single()
            .execute()
        )

        updated_user = UserListItem.model_validate(
            updated_response.data
        )

        await write_audit_log(
            request=request,
            actor=current_user,
            action="DEACTIVATE_USER",
            entity_type="USER",
            entity_id=updated_user.id,
            old_values={
                "activo": True,
            },
            new_values={
                "activo": False,
            },
            description="Desactivación de usuario.",
        )

        return updated_user

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
        400: {
            "description": "Operación no permitida.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No autorizado para eliminar este usuario.",
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": "Error interno al eliminar el usuario.",
        },
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
    Realiza el borrado lógico de un usuario.

    Reglas:
        - DIRECTIVA no puede eliminar SUPERADMIN.
        - Un usuario no puede eliminarse a sí mismo.
        - La identidad de Supabase Auth se conserva.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. Impedir autoeliminación.
        # --------------------------------------------------------
        if user_id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No puede eliminar su propio usuario.",
            )

        # --------------------------------------------------------
        # 2. Obtener estado anterior.
        # --------------------------------------------------------
        target_response = (
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
                deleted_at,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq("id", str(user_id))
            .maybe_single()
            .execute()
        )

        if not target_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_user = target_response.data

        if target_user.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_role = target_user.get("roles")

        if not target_role:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="No fue posible determinar el rol.",
            )

        if (
            current_user.role_code == "DIRECTIVA"
            and target_role["codigo"] == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DIRECTIVA no puede eliminar usuarios SUPERADMIN.",
            )

        # --------------------------------------------------------
        # 3. Generar timestamp una sola vez.
        #
        # Así el valor registrado en DB y auditoría coincide.
        # --------------------------------------------------------
        deleted_at = datetime.now(
            timezone.utc
        ).isoformat()

        # --------------------------------------------------------
        # 4. Borrado lógico.
        # --------------------------------------------------------
        delete_response = (
            supabase.table("usuarios")
            .update(
                {
                    "activo": False,
                    "deleted_at": deleted_at,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(user_id))
            .execute()
        )

        if not delete_response.data:
            raise RuntimeError(
                "No fue posible realizar el borrado lógico."
            )

        # --------------------------------------------------------
        # 5. Auditoría.
        # --------------------------------------------------------
        await write_audit_log(
            request=request,
            actor=current_user,
            action="DELETE_USER",
            entity_type="USER",
            entity_id=user_id,
            old_values={
                "rut": target_user.get("rut"),
                "nombres": target_user.get("nombres"),
                "apellido_paterno": target_user.get(
                    "apellido_paterno"
                ),
                "apellido_materno": target_user.get(
                    "apellido_materno"
                ),
                "email": target_user.get("email"),
                "telefono": target_user.get("telefono"),
                "activo": target_user.get("activo"),
                "deleted_at": None,
                "role_code": target_role.get("codigo"),
            },
            new_values={
                "activo": False,
                "deleted_at": deleted_at,
                "role_code": target_role.get("codigo"),
            },
            description="Borrado lógico de usuario.",
        )

        return None

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible eliminar el usuario.",
        )