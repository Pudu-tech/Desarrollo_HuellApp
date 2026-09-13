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

from fastapi import APIRouter, Depends

from app.core.security import get_current_user
from app.schemas.auth import AuthenticatedUser


router = APIRouter(
    prefix="/auth",
    tags=["Auth"],
)


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