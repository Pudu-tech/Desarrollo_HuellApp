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

from collections.abc import Callable

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from supabase_auth.errors import AuthApiError


# Extrae credenciales enviadas mediante:
# Authorization: Bearer <token>
bearer_scheme = HTTPBearer(
    auto_error=False,
)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(
        bearer_scheme
    ),
) -> AuthenticatedUser:
    """
    Obtiene y valida al usuario autenticado actual.

    El flujo es:
    1. Extraer el token Bearer de la solicitud.
    2. Validar el token mediante Supabase Auth.
    3. Obtener el perfil de negocio desde public.usuarios.
    4. Obtener nombre, correo y código del rol asociado.
    5. Construir un AuthenticatedUser.

    SECURITY:
    - El token no se retorna ni se almacena.
    - El perfil y rol se consultan desde la base de datos.
    - El estado del usuario se valida en backend.
    """

    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticación requerida.",
            headers={
                "WWW-Authenticate": "Bearer"
            },
        )

    access_token = credentials.credentials

    try:
        supabase = get_supabase_client()

        # Supabase valida el access token y retorna
        # la identidad asociada.
        try:
            auth_response = supabase.auth.get_user(access_token)
        except AuthApiError as exc:
            if exc.status in (400, 401, 403):
                raise HTTPException(401, 'La sesión venció o no es válida.', headers={'WWW-Authenticate': 'Bearer'}) from exc
            raise HTTPException(503, 'El servicio de autenticación no está disponible temporalmente. Reintenta.') from exc

        auth_user = auth_response.user

        if auth_user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token de autenticación inválido.",
                headers={
                    "WWW-Authenticate": "Bearer"
                },
            )

        # SECURITY:
        # Perfil, nombre y rol se consultan desde
        # public.usuarios.
        profile_response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                email,
                nombres,
                apellido_paterno,
                activo,
                deleted_at,
                roles!inner(codigo,rol_permiso(permisos(codigo,activo)))
                """
            )
            .eq(
                "id",
                str(auth_user.id),
            )
            .single()
            .execute()
        )

        profile = profile_response.data

        if not profile:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "El usuario no posee un perfil "
                    "válido en HuellAPP."
                ),
            )

        if (
            not profile.get("activo")
            or profile.get("deleted_at") is not None
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "El usuario se encuentra inactivo."
                ),
            )

        role_data = profile.get("roles")

        if (
            not role_data
            or not role_data.get("codigo")
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "El usuario no posee un rol válido."
                ),
            )

        return AuthenticatedUser(
            id=auth_user.id,
            email=profile["email"],
            nombres=profile["nombres"],
            apellido_paterno=profile[
                "apellido_paterno"
            ],
            role_code=role_data["codigo"],
            effective_permissions=frozenset(
                permission["codigo"] for relation in (role_data.get("rol_permiso") or [])
                if (permission := relation.get("permisos")) and permission.get("activo")
            ),
        )

    except HTTPException:
        raise

    except Exception:
        # SECURITY:
        # No devolvemos detalles internos del error.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "No fue posible consultar la sesión temporalmente. Reintenta en unos momentos."
            ),
        )


# Autorización centralizada: la navegación del frontend nunca reemplaza este control.
def require_permission(
    permission_code: str,
) -> Callable:
    """
    Crea una dependencia de FastAPI que exige
    un permiso específico.

    SECURITY:
    - El permiso se consulta desde la base de datos.
    - No se confía en permisos enviados por frontend.
    """

    def permission_dependency(
        current_user: AuthenticatedUser = Depends(
            get_current_user
        ),
    ) -> AuthenticatedUser:
        """
        Valida que el rol actual del usuario posea
        el permiso requerido.
        """

        # El perfil y los permisos se consultan juntos en esta misma solicitud.
        # No se cachean entre solicitudes: una revocación se aplica en la siguiente.
        if permission_code not in current_user.effective_permissions:
            raise HTTPException(403, "No posee permisos para realizar esta acción.")
        return current_user

    return permission_dependency
