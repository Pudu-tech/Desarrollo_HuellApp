"""
Funciones de seguridad y autenticación del backend de HuellAPP.

Este módulo centraliza las utilidades relacionadas con:
- extracción del token Bearer enviado por el cliente;
- validación del JWT emitido por Supabase Auth;
- obtención del usuario autenticado desde la base de datos;
- preparación de la autorización basada en roles y permisos.

SECURITY:
- Nunca se confía en roles enviados por el frontend.
- El usuario se identifica a partir del token validado por Supabase.
- La información sensible del token no se registra en logs.
- Las operaciones protegidas utilizarán este módulo como dependencia
  común para evitar duplicar lógica de autenticación.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser


# Extrae credenciales enviadas mediante:
# Authorization: Bearer <token>
bearer_scheme = HTTPBearer(
    auto_error=False,
)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> AuthenticatedUser:
    """
    Obtiene y valida al usuario autenticado actual.

    El flujo es:
    1. Extraer el token Bearer de la solicitud.
    2. Validar el token mediante Supabase Auth.
    3. Obtener el perfil de negocio desde `public.usuarios`.
    4. Obtener el código del rol asociado.
    5. Construir un `AuthenticatedUser`.

    Args:
        credentials:
            Credenciales HTTP Bearer extraídas automáticamente
            desde la cabecera Authorization.

    Returns:
        AuthenticatedUser:
            Usuario autenticado y validado por el backend.

    Raises:
        HTTPException:
            401 si el token no existe, es inválido o está expirado.
            403 si el usuario no posee un perfil válido o está inactivo.

    SECURITY:
        - El token no se retorna ni se almacena.
        - El rol se consulta desde la base de datos.
        - El estado del usuario se valida en backend.
    """

    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticación requerida.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = credentials.credentials

    try:
        supabase = get_supabase_client()

        # Supabase valida el access token y retorna la identidad asociada.
        auth_response = supabase.auth.get_user(access_token)

        auth_user = auth_response.user

        if auth_user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de autenticación inválido.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # SECURITY:
        # El perfil y rol se consultan desde la base de datos.
        # Nunca utilizamos un rol enviado directamente por el frontend.
        profile_response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                email,
                activo,
                deleted_at,
                roles!inner(codigo)
                """
            )
            .eq("id", str(auth_user.id))
            .single()
            .execute()
        )

        profile = profile_response.data

        if not profile:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El usuario no posee un perfil válido en HuellAPP.",
            )

        if not profile.get("activo") or profile.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El usuario se encuentra inactivo.",
            )

        role_data = profile.get("roles")

        if not role_data or not role_data.get("codigo"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El usuario no posee un rol válido.",
            )

        return AuthenticatedUser(
            id=auth_user.id,
            email=profile["email"],
            role_code=role_data["codigo"],
        )

    except HTTPException:
        # Las excepciones HTTP controladas se propagan sin modificarlas.
        raise

    except Exception:
        # SECURITY:
        # No devolvemos detalles internos del error al cliente,
        # ya que podrían revelar información del sistema.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No fue posible validar la sesión.",
            headers={"WWW-Authenticate": "Bearer"},
        )

from collections.abc import Callable


def require_permission(permission_code: str) -> Callable:
    """
    Crea una dependencia de FastAPI que exige un permiso específico.

    Args:
        permission_code:
            Código del permiso requerido.
            Ej.: VIEW_USERS, CREATE_ASSIGNMENT.

    Returns:
        Callable:
            Dependencia que valida si el usuario autenticado posee
            el permiso solicitado.

    SECURITY:
        - El permiso se consulta desde la base de datos.
        - No se confía en permisos enviados por el frontend.
        - Si el usuario no posee el permiso, se retorna HTTP 403.
    """

    async def permission_dependency(
        current_user: AuthenticatedUser = Depends(get_current_user),
    ) -> AuthenticatedUser:
        """
        Valida que el rol actual del usuario posea el permiso requerido.

        Returns:
            AuthenticatedUser:
                Usuario autenticado si posee el permiso.

        Raises:
            HTTPException:
                403 si el rol del usuario no posee el permiso.
        """

        supabase = get_supabase_client()

        try:
            response = (
                supabase.table("roles")
                .select(
                    """
                    id,
                    rol_permiso!inner(
                        permisos!inner(codigo)
                    )
                    """
                )
                .eq("codigo", current_user.role_code)
                .eq("rol_permiso.permisos.codigo", permission_code)
                .limit(1)
                .execute()
            )

            if not response.data:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permisos para realizar esta acción.",
                )

            return current_user

        except HTTPException:
            raise

        except Exception:
            # SECURITY:
            # No exponemos detalles internos de la consulta.
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="No fue posible validar los permisos del usuario.",
            )

    return permission_dependency