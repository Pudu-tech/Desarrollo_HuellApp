"""
Endpoints de autenticación del backend de HuellAPP.

Este módulo expone rutas protegidas relacionadas con la sesión
del usuario autenticado.

SECURITY:
- Los endpoints protegidos dependen de `get_current_user`.
- El backend valida el token con Supabase Auth.
- El rol del usuario se obtiene desde la base de datos.
- No se confía en información de identidad enviada por el frontend.
"""

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import get_current_user
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser


router = APIRouter(
    prefix="/auth",
    tags=["Auth"],
)


@router.get("/permissions", response_model=list[str])
async def get_authenticated_permissions(
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> list[str]:
    """Permisos efectivos de la sesión para presentar acciones en la UI."""
    try:
        result = (
            get_supabase_client().table("roles")
            .select("rol_permiso(permisos(codigo,activo))")
            .eq("codigo", current_user.role_code).execute()
        )
        return sorted({
            permission["codigo"]
            for role in (result.data or [])
            for relation in (role.get("rol_permiso") or [])
            if (permission := relation.get("permisos")) and permission.get("activo")
        })
    except Exception:
        raise HTTPException(500, "No fue posible consultar los permisos.")


@router.get("/me", response_model=AuthenticatedUser)
async def get_authenticated_user(
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> AuthenticatedUser:
    """
    Retorna la identidad del usuario autenticado.

    Este endpoint se utilizará inicialmente para verificar que:
    - el access token es válido;
    - existe un perfil asociado en `public.usuarios`;
    - el usuario está activo;
    - posee un rol válido.

    Args:
        current_user:
            Usuario autenticado obtenido mediante la dependencia
            de seguridad `get_current_user`.

    Returns:
        AuthenticatedUser:
            Identificación básica y rol actual del usuario.
    """

    return current_user
