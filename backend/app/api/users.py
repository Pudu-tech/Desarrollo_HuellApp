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
- Los administradores no definen contraseñas de usuarios nuevos.
- Los usuarios nuevos reciben una invitación para establecer
  personalmente sus credenciales.
"""

from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Request,
    status,
)

from app.core.config import get_settings
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.users import (
    UserCreate,
    UserCreateResponse,
    UserEmailUpdate,
    UserListItem,
    UserRoleUpdate,
    UserUpdate,
)


router = APIRouter(
    prefix="/users",
    tags=["Users"],
)


# ============================================================
# FUNCIONES AUXILIARES
# ============================================================


def _request_rpc_context(request: Request) -> dict:
    """
    Construye metadatos comunes enviados a las RPC de escritura.
    El actor nunca se obtiene desde el frontend; únicamente se
    propagan identificadores y metadatos de la solicitud
    autenticada actual.
    Estos datos permiten mantener trazabilidad en auditoría sin
    confiar en información manipulable enviada por el cliente.
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
        "user_agent": request.headers.get(
            "user-agent"
        ),
    }


def _get_user_result(
    supabase,
    *,
    user_id: UUID,
) -> UserListItem:
    """
    Recupera el contrato público de un usuario no eliminado.
    Esta función centraliza la consulta utilizada después de
    operaciones de actualización para evitar duplicar consultas.
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
        .eq(
            "id",
            str(user_id),
        )
        .is_(
            "deleted_at",
            "null",
        )
        .single()
        .execute()
    )
    return UserListItem.model_validate(
        response.data
    )


# ============================================================
# CONSULTAS
# ============================================================


@router.get(
    "",
    response_model=list[UserListItem],
    responses={
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "El usuario no posee el permiso VIEW_USERS."
            ),
        },
        500: {
            "description": (
                "Error interno al obtener el listado "
                "de usuarios."
            ),
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
            .is_(
                "deleted_at",
                "null",
            )
            .order(
                "apellido_paterno"
            )
            .order(
                "nombres"
            )
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
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible obtener el listado "
                "de usuarios."
            ),
        )


@router.get(
    "/{user_id}",
    response_model=UserListItem,
    responses={
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "El usuario no posee el permiso VIEW_USERS."
            ),
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": (
                "Error interno al obtener el usuario."
            ),
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
            .eq(
                "id",
                str(user_id),
            )
            .is_(
                "deleted_at",
                "null",
            )
            .maybe_single()
            .execute()
        )
        if not response.data:
            raise HTTPException(
                status_code=(
                    status.HTTP_404_NOT_FOUND
                ),
                detail="Usuario no encontrado.",
            )
        return UserListItem.model_validate(
            response.data
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible obtener el usuario."
            ),
        )


# ============================================================
# CREACIÓN / INVITACIÓN
# ============================================================


@router.post(
    "",
    response_model=UserCreateResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {
            "description": (
                "Datos inválidos o rol no permitido."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "El usuario no posee permiso "
                "para crear usuarios."
            ),
        },
        409: {
            "description": (
                "El RUT o correo ya se encuentra registrado."
            ),
        },
        500: {
            "description": (
                "Error interno al crear e invitar "
                "el usuario."
            ),
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
    Crea e invita un usuario mediante un flujo híbrido seguro.
    Supabase Auth y PostgreSQL no comparten una transacción ACID.
    FLUJO:
    1. Valida el rol solicitado.
    2. Prevalida duplicados conocidos.
    3. Crea la identidad mediante una invitación de Supabase.
    4. Supabase envía el correo de invitación.
    5. Crea public.usuarios + audit_logs mediante una RPC
       PostgreSQL atómica.
    6. Si PostgreSQL falla antes de confirmar el perfil,
       elimina compensatoriamente la identidad creada en Auth.
    SECURITY:
    - El administrador nunca define la contraseña del usuario.
    - La contraseña no viaja por este endpoint.
    - El usuario invitado configura personalmente su contraseña.
    - La autorización se valida en FastAPI y nuevamente dentro
      de las RPC críticas.
    - No se registran tokens, contraseñas ni secretos.
    LIMITACIÓN TRANSACCIONAL:
    El envío de correo es un efecto externo y no puede formar
    parte de la transacción PostgreSQL. Si la creación posterior
    del perfil falla, la identidad Auth se elimina para invalidar
    la invitación generada.
    """
    supabase = get_supabase_client()
    settings = get_settings()
    auth_user_id: str | None = None
    db_creation_committed = False

    try:

        # --------------------------------------------------------
        # 1. VALIDAR ROL SOLICITADO
        # --------------------------------------------------------
        #
        # La validación ocurre antes de crear una identidad
        # en Supabase Auth.
        #
        # La RPC vuelve a validar esta regla como defensa
        # en profundidad.
        # --------------------------------------------------------
        role_response = (
            supabase.table("roles")
            .select(
                "id,codigo,nombre"
            )
            .eq(
                "codigo",
                payload.role_code,
            )
            .eq(
                "activo",
                True,
            )
            .maybe_single()
            .execute()
        )
        if not role_response.data:
            raise HTTPException(
                status_code=(
                    status.HTTP_400_BAD_REQUEST
                ),
                detail=(
                    "El rol solicitado no existe "
                    "o está inactivo."
                ),
            )
        requested_role = role_response.data
        # DIRECTIVA puede administrar usuarios, pero no tiene
        # autorización para crear cuentas SUPERADMIN.
        if (
            current_user.role_code == "DIRECTIVA"
            and requested_role["codigo"]
            == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=(
                    status.HTTP_403_FORBIDDEN
                ),
                detail=(
                    "DIRECTIVA no puede crear "
                    "usuarios SUPERADMIN."
                ),
            )

        # --------------------------------------------------------
        # 2. PREVALIDAR DUPLICADOS
        # --------------------------------------------------------
        #
        # Estas verificaciones permiten responder antes de tocar
        # Supabase Auth.
        #
        # PostgreSQL continúa siendo responsable de garantizar
        # definitivamente la integridad mediante sus propias
        # restricciones y la RPC.
        # --------------------------------------------------------
        rut_response = (
            supabase.table("usuarios")
            .select("id")
            .eq(
                "rut",
                payload.rut,
            )
            .is_(
                "deleted_at",
                "null",
            )
            .limit(1)
            .execute()
        )
        if rut_response.data:
            raise HTTPException(
                status_code=(
                    status.HTTP_409_CONFLICT
                ),
                detail=(
                    "El RUT ya se encuentra registrado."
                ),
            )
        email_response = (
            supabase.table("usuarios")
            .select("id")
            .ilike(
                "email",
                str(payload.email),
            )
            .is_(
                "deleted_at",
                "null",
            )
            .limit(1)
            .execute()
        )
        if email_response.data:
            raise HTTPException(
                status_code=(
                    status.HTTP_409_CONFLICT
                ),
                detail=(
                    "El correo ya se encuentra registrado."
                ),
            )

        # --------------------------------------------------------
        # 3. CONSTRUIR URL DE ESTABLECIMIENTO DE CONTRASEÑA
        # --------------------------------------------------------
        #
        # FRONTEND_URL se obtiene desde configuración para evitar
        # dominios hardcodeados.
        #
        # Ejemplos:
        #
        # LOCAL
        # http://localhost:5173
        #
        # DEV
        # https://huellapp-frontend-git-develop-...
        #
        # PROD
        # dominio productivo de HuellAPP.
        # --------------------------------------------------------
        frontend_url = (
            settings.frontend_url.rstrip("/")
        )
        invitation_redirect_url = (
            f"{frontend_url}"
            "/establecer-password"
        )

        # --------------------------------------------------------
        # 4. CREAR IDENTIDAD Y ENVIAR INVITACIÓN
        # --------------------------------------------------------
        #
        # El administrador no proporciona una contraseña.
        #
        # Supabase Auth genera la identidad y envía un correo de
        # invitación al usuario para que este establezca sus
        # propias credenciales.
        # --------------------------------------------------------
        auth_response = (
            supabase.auth.admin.invite_user_by_email(
                str(payload.email),
                {
                    "redirect_to": (
                        invitation_redirect_url
                    ),
                },
            )
        )
        if not auth_response.user:
            raise RuntimeError(
                "No fue posible crear la identidad "
                "en Supabase Auth."
            )
        auth_user_id = str(
            auth_response.user.id
        )

        # --------------------------------------------------------
        # 5. CREAR PERFIL + AUDITORÍA
        # --------------------------------------------------------
        #
        # La creación de public.usuarios y audit_logs ocurre
        # mediante una única RPC PostgreSQL para mantener
        # atomicidad dentro de la base de datos.
        # --------------------------------------------------------
        context = _request_rpc_context(
            request
        )
        response = supabase.rpc(
            "crear_usuario_atomico",
            {
                "p_user_id": (
                    auth_user_id
                ),
                "p_rut": (
                    payload.rut
                ),
                "p_nombres": (
                    payload.nombres
                ),
                "p_apellido_paterno": (
                    payload.apellido_paterno
                ),
                "p_apellido_materno": (
                    payload.apellido_materno
                ),
                "p_email": str(
                    payload.email
                ),
                "p_telefono": (
                    payload.telefono
                ),
                "p_role_code": (
                    payload.role_code
                ),
                "p_actor_user_id": str(
                    current_user.id
                ),
                "p_request_id": (
                    context["request_id"]
                ),
                "p_ip_address": (
                    context["ip_address"]
                ),
                "p_user_agent": (
                    context["user_agent"]
                ),
            },
        ).execute()
        resultado = response.data
        if not isinstance(
            resultado,
            dict,
        ):
            raise RuntimeError(
                "La RPC de creación de usuario "
                "devolvió una respuesta inválida."
            )

        # --------------------------------------------------------
        # 6. INTERPRETAR RESULTADO DE LA RPC
        # --------------------------------------------------------
        if resultado.get("ok") is not True:
            error_code = resultado.get(
                "error_code"
            )
            if error_code in {
                "RUT_EXISTS",
                "EMAIL_EXISTS",
                "USER_ID_EXISTS",
                "DUPLICATE_USER",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_409_CONFLICT
                    ),
                    detail=(
                        "El RUT o correo ya se "
                        "encuentra registrado."
                    ),
                )
            if error_code == "ROLE_NOT_FOUND":
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail=(
                        "El rol solicitado no existe "
                        "o está inactivo."
                    ),
                )
            if error_code in {
                "INVALID_USER_ID",
                "INVALID_RUT",
                "INVALID_NAME",
                "INVALID_EMAIL",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail=(
                        "Los datos enviados para crear "
                        "el usuario no son válidos."
                    ),
                )
            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_403_FORBIDDEN
                    ),
                    detail=(
                        "No autorizado para crear "
                        "este usuario."
                    ),
                )
            raise RuntimeError(
                "La RPC no pudo completar "
                "la creación del usuario."
            )
        # La RPC confirmó la creación de perfil + auditoría.
        # A partir de este punto no corresponde eliminar
        # compensatoriamente la identidad de Supabase Auth.
        db_creation_committed = True
        usuario = resultado.get(
            "usuario"
        )
        if not isinstance(
            usuario,
            dict,
        ):
            raise RuntimeError(
                "La RPC no devolvió "
                "el usuario creado."
            )
        return UserCreateResponse.model_validate(
            usuario
        )

    except HTTPException:

        # --------------------------------------------------------
        # COMPENSACIÓN DE SUPABASE AUTH
        # --------------------------------------------------------
        #
        # Si Supabase Auth creó la identidad pero PostgreSQL
        # todavía no confirmó el perfil, se elimina únicamente
        # esa identidad recién creada.
        #
        # Esto evita usuarios huérfanos en Auth.
        # --------------------------------------------------------
        if (
            auth_user_id is not None
            and not db_creation_committed
        ):
            try:
                supabase.auth.admin.delete_user(
                    auth_user_id
                )
            except Exception:
                # Se conserva como error principal la excepción
                # que provocó la compensación.
                #
                # Posteriormente esta situación puede integrarse
                # a un sistema de observabilidad/logging.
                pass
        raise

    except Exception:

        # --------------------------------------------------------
        # ERROR NO CONTROLADO + COMPENSACIÓN
        # --------------------------------------------------------
        if (
            auth_user_id is not None
            and not db_creation_committed
        ):
            try:
                supabase.auth.admin.delete_user(
                    auth_user_id
                )
            except Exception:
                pass
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible crear e invitar "
                "el usuario."
            ),
        )


# ============================================================
# EDICIÓN DE DATOS BÁSICOS
# ============================================================


@router.patch(
    "/{user_id}",
    response_model=UserListItem,
    responses={
        400: {
            "description": (
                "No se enviaron campos válidos "
                "para actualizar."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "No autorizado para modificar este usuario."
            ),
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": (
                "Error interno al actualizar el usuario."
            ),
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
    Actualiza datos básicos y auditoría dentro de una
    sola transacción.
    """
    supabase = get_supabase_client()

    try:
        cambios = payload.model_dump(
            exclude_unset=True
        )
        if not cambios:
            raise HTTPException(
                status_code=(
                    status.HTTP_400_BAD_REQUEST
                ),
                detail=(
                    "No se enviaron campos "
                    "para actualizar."
                ),
            )
        context = _request_rpc_context(
            request
        )
        response = supabase.rpc(
            "actualizar_usuario_atomico",
            {
                "p_user_id": str(
                    user_id
                ),
                "p_cambios": cambios,
                "p_actor_user_id": str(
                    current_user.id
                ),
                "p_request_id": (
                    context["request_id"]
                ),
                "p_ip_address": (
                    context["ip_address"]
                ),
                "p_user_agent": (
                    context["user_agent"]
                ),
            },
        ).execute()
        resultado = response.data
        if not isinstance(
            resultado,
            dict,
        ):
            raise RuntimeError(
                "Respuesta inválida de "
                "actualización de usuario."
            )
        if resultado.get("ok") is not True:
            error_code = resultado.get(
                "error_code"
            )
            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=(
                        status.HTTP_404_NOT_FOUND
                    ),
                    detail="Usuario no encontrado.",
                )
            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_403_FORBIDDEN
                    ),
                    detail=(
                        "No autorizado para modificar "
                        "este usuario."
                    ),
                )
            if error_code == "NO_EFFECTIVE_CHANGES":
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail="No se realizaron cambios.",
                )

            if error_code in {
                "NO_CHANGES",
                "INVALID_FIELDS",
                "INVALID_REQUIRED_FIELD",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail=(
                        "Los datos enviados para "
                        "actualizar no son válidos."
                    ),
                )
            raise RuntimeError(
                "No fue posible actualizar "
                "el usuario."
            )
        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible actualizar el usuario."
            ),
        )


# ============================================================
# CAMBIO DE CORREO
# ============================================================


@router.patch(
    "/{user_id}/email",
    response_model=UserListItem,
    responses={
        400: {
            "description": (
                "Correo inválido o igual al correo actual."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "No autorizado para cambiar el correo."
            ),
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        409: {
            "description": (
                "Correo ocupado o identidad desincronizada."
            ),
        },
        500: {
            "description": (
                "Error interno al cambiar el correo."
            ),
        },
    },
)
async def update_user_email(
    request: Request,
    user_id: UUID,
    payload: UserEmailUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_USER")
    ),
) -> UserListItem:
    """
    Cambia el correo de un usuario manteniendo el mismo UUID.

    FLUJO
    --------------------------------------------------------
    1. Valida usuario, permisos y duplicados funcionales.
    2. Verifica que Supabase Auth y public.usuarios estén
       sincronizados antes de modificar datos.
    3. Actualiza el correo en Supabase Auth.
    4. Actualiza public.usuarios + auditoría mediante la RPC
       cambiar_email_usuario_atomico.
    5. Si PostgreSQL falla después del cambio en Auth, intenta
       restaurar el correo anterior en Auth.

    SECURITY
    --------------------------------------------------------
    - El cambio se ejecuta exclusivamente desde backend.
    - Nunca se expone la clave de service role al frontend.
    - DIRECTIVA no puede modificar cuentas SUPERADMIN.
    - La auditoría se registra únicamente si el cambio
      funcional queda confirmado en PostgreSQL.
    """

    supabase = get_supabase_client()
    new_email = str(payload.email).strip().lower()
    old_email: str | None = None
    auth_email_updated = False

    def restore_auth_email() -> None:
        """
        Restaura el correo anterior en Supabase Auth cuando el
        cambio funcional en PostgreSQL no puede confirmarse.
        """

        nonlocal auth_email_updated

        if not auth_email_updated or old_email is None:
            return

        try:
            supabase.auth.admin.update_user_by_id(
                str(user_id),
                {
                    "email": old_email,
                },
            )
            auth_email_updated = False
        except Exception as rollback_error:
            raise HTTPException(
                status_code=(
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                ),
                detail=(
                    "No fue posible completar el cambio de correo "
                    "ni restaurar automáticamente el correo anterior. "
                    "Revise la sincronización entre Supabase Auth "
                    "y HuellAPP."
                ),
            ) from rollback_error

    try:
        # --------------------------------------------------------
        # 1. OBTENER USUARIO OBJETIVO
        # --------------------------------------------------------
        target_response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                email,
                deleted_at,
                roles(
                    codigo,
                    nombre
                )
                """
            )
            .eq(
                "id",
                str(user_id),
            )
            .maybe_single()
            .execute()
        )

        if (
            not target_response.data
            or target_response.data.get("deleted_at") is not None
        ):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Usuario no encontrado.",
            )

        target_user = target_response.data
        target_role = target_user.get("roles")
        old_email = str(
            target_user["email"]
        ).strip().lower()

        if (
            current_user.role_code == "DIRECTIVA"
            and target_role
            and target_role.get("codigo") == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "No autorizado para cambiar el correo "
                    "de este usuario."
                ),
            )

        if old_email == new_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "El nuevo correo debe ser diferente "
                    "al correo actual."
                ),
            )

        # --------------------------------------------------------
        # 2. PREVALIDAR DUPLICADO FUNCIONAL
        # --------------------------------------------------------
        email_response = (
            supabase.table("usuarios")
            .select("id")
            .ilike(
                "email",
                new_email,
            )
            .is_(
                "deleted_at",
                "null",
            )
            .neq(
                "id",
                str(user_id),
            )
            .limit(1)
            .execute()
        )

        if email_response.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "El correo ya se encuentra registrado."
                ),
            )

        # --------------------------------------------------------
        # 3. VERIFICAR SINCRONIZACIÓN CON SUPABASE AUTH
        # --------------------------------------------------------
        auth_lookup = (
            supabase.auth.admin.get_user_by_id(
                str(user_id)
            )
        )
        auth_user = getattr(
            auth_lookup,
            "user",
            None,
        )

        if auth_user is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "La identidad de autenticación del usuario "
                    "no se encuentra disponible."
                ),
            )

        auth_old_email_raw = getattr(
            auth_user,
            "email",
            None,
        )

        if not auth_old_email_raw:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "La identidad de autenticación no posee "
                    "un correo válido."
                ),
            )

        auth_old_email = str(
            auth_old_email_raw
        ).strip().lower()

        if auth_old_email != old_email:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "El correo del usuario no está sincronizado "
                    "entre Supabase Auth y HuellAPP."
                ),
            )

        # --------------------------------------------------------
        # 4. ACTUALIZAR SUPABASE AUTH
        # --------------------------------------------------------
        try:
            auth_update = (
                supabase.auth.admin.update_user_by_id(
                    str(user_id),
                    {
                        "email": new_email,
                    },
                )
            )
        except Exception as auth_error:
            auth_message = str(
                auth_error
            ).lower()

            if (
                "already" in auth_message
                or "registered" in auth_message
                or "exists" in auth_message
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El correo ya se encuentra registrado "
                        "en el sistema de autenticación."
                    ),
                ) from auth_error

            raise HTTPException(
                status_code=(
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                ),
                detail=(
                    "No fue posible actualizar el correo "
                    "en Supabase Auth."
                ),
            ) from auth_error

        # Desde este punto asumimos que Auth pudo aplicar el cambio.
        # Si cualquier validación posterior falla, intentaremos
        # restaurar el correo anterior.
        auth_email_updated = True

        updated_auth_user = getattr(
            auth_update,
            "user",
            None,
        )

        if updated_auth_user is None:
            raise HTTPException(
                status_code=(
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                ),
                detail=(
                    "Supabase Auth no confirmó la actualización "
                    "del correo."
                ),
            )

        updated_auth_email = getattr(
            updated_auth_user,
            "email",
            None,
        )

        if (
            not updated_auth_email
            or str(updated_auth_email).strip().lower()
            != new_email
        ):
            raise HTTPException(
                status_code=(
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                ),
                detail=(
                    "Supabase Auth devolvió un correo distinto "
                    "al solicitado."
                ),
            )

        # --------------------------------------------------------
        # 5. ACTUALIZAR PERFIL + AUDITORÍA EN POSTGRESQL
        # --------------------------------------------------------
        context = _request_rpc_context(
            request
        )

        response = supabase.rpc(
            "cambiar_email_usuario_atomico",
            {
                "p_user_id": str(
                    user_id
                ),
                "p_new_email": new_email,
                "p_actor_user_id": str(
                    current_user.id
                ),
                "p_request_id": (
                    context["request_id"]
                ),
                "p_ip_address": (
                    context["ip_address"]
                ),
                "p_user_agent": (
                    context["user_agent"]
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(
            resultado,
            dict,
        ):
            restore_auth_email()
            raise HTTPException(
                status_code=(
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                ),
                detail=(
                    "La base de datos devolvió una respuesta "
                    "inválida al cambiar el correo."
                ),
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get(
                "error_code"
            )

            restore_auth_email()

            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Usuario no encontrado.",
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No autorizado para cambiar el correo "
                        "de este usuario."
                    ),
                )

            if error_code == "EMAIL_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El correo ya se encuentra registrado."
                    ),
                )

            if error_code == "SAME_EMAIL":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El nuevo correo debe ser diferente "
                        "al correo actual."
                    ),
                )

            if error_code == "INVALID_EMAIL":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El correo ingresado no es válido."
                    ),
                )

            raise HTTPException(
                status_code=(
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                ),
                detail=(
                    "No fue posible confirmar el cambio de correo "
                    "en HuellAPP."
                ),
            )

        # Ambos sistemas ya quedaron sincronizados.
        auth_email_updated = False

        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        if auth_email_updated:
            restore_auth_email()
        raise

    except Exception as unexpected_error:
        if auth_email_updated:
            restore_auth_email()

        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible cambiar el correo del usuario."
            ),
        ) from unexpected_error


# ============================================================
# CAMBIO DE ROL
# ============================================================


@router.patch(
    "/{user_id}/role",
    response_model=UserListItem,
    responses={
        400: {
            "description": (
                "Rol solicitado inválido."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "No autorizado para cambiar el rol."
            ),
        },
        404: {
            "description": (
                "Usuario o rol no encontrado."
            ),
        },
        500: {
            "description": (
                "Error interno al cambiar el rol."
            ),
        },
    },
)


async def update_user_role(
    request: Request,
    user_id: UUID,
    payload: UserRoleUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission(
            "CHANGE_USER_ROLE"
        )
    ),
) -> UserListItem:
    """
    Cambia el rol y registra auditoría dentro de una
    sola transacción.
    """
    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(
            request
        )
        response = supabase.rpc(
            "cambiar_rol_usuario_atomico",
            {
                "p_user_id": str(
                    user_id
                ),
                "p_role_code": (
                    payload.role_code
                ),
                "p_actor_user_id": str(
                    current_user.id
                ),
                "p_request_id": (
                    context["request_id"]
                ),
                "p_ip_address": (
                    context["ip_address"]
                ),
                "p_user_agent": (
                    context["user_agent"]
                ),
            },
        ).execute()
        resultado = response.data
        if not isinstance(
            resultado,
            dict,
        ):
            raise RuntimeError(
                "Respuesta inválida "
                "de cambio de rol."
            )
        if resultado.get("ok") is not True:
            error_code = resultado.get(
                "error_code"
            )
            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=(
                        status.HTTP_404_NOT_FOUND
                    ),
                    detail="Usuario no encontrado.",
                )
            if error_code == "ROLE_NOT_FOUND":
                raise HTTPException(
                    status_code=(
                        status.HTTP_404_NOT_FOUND
                    ),
                    detail=(
                        "El rol solicitado no existe "
                        "o está inactivo."
                    ),
                )
            if error_code == "SAME_ROLE":
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail=(
                        "El usuario ya posee "
                        "el rol solicitado."
                    ),
                )
            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_403_FORBIDDEN
                    ),
                    detail=(
                        "No autorizado para "
                        "cambiar el rol."
                    ),
                )
            raise RuntimeError(
                "No fue posible cambiar el rol."
            )
        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible cambiar "
                "el rol del usuario."
            ),
        )


# ============================================================
# ACTIVACIÓN
# ============================================================


@router.patch(
    "/{user_id}/activate",
    response_model=UserListItem,
    responses={
        400: {
            "description": (
                "El usuario ya se encuentra activo."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "No autorizado para activar "
                "este usuario."
            ),
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": (
                "Error interno al activar el usuario."
            ),
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
    Activa un usuario y registra auditoría de forma atómica.
    """
    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(
            request
        )
        response = supabase.rpc(
            "activar_usuario_atomico",
            {
                "p_user_id": str(
                    user_id
                ),
                "p_actor_user_id": str(
                    current_user.id
                ),
                "p_request_id": (
                    context["request_id"]
                ),
                "p_ip_address": (
                    context["ip_address"]
                ),
                "p_user_agent": (
                    context["user_agent"]
                ),
            },
        ).execute()
        resultado = response.data
        if not isinstance(
            resultado,
            dict,
        ):
            raise RuntimeError(
                "Respuesta inválida "
                "de activación de usuario."
            )
        if resultado.get("ok") is not True:
            error_code = resultado.get(
                "error_code"
            )
            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=(
                        status.HTTP_404_NOT_FOUND
                    ),
                    detail="Usuario no encontrado.",
                )
            if error_code == "ALREADY_ACTIVE":
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail=(
                        "El usuario ya se encuentra activo."
                    ),
                )
            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_403_FORBIDDEN
                    ),
                    detail=(
                        "No autorizado para activar "
                        "este usuario."
                    ),
                )
            raise RuntimeError(
                "No fue posible activar el usuario."
            )
        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible activar el usuario."
            ),
        )


# ============================================================
# DESACTIVACIÓN
# ============================================================


@router.patch(
    "/{user_id}/deactivate",
    response_model=UserListItem,
    responses={
        400: {
            "description": (
                "El usuario ya se encuentra inactivo."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "No autorizado para desactivar "
                "este usuario."
            ),
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": (
                "Error interno al desactivar el usuario."
            ),
        },
    },
)


async def deactivate_user(
    request: Request,
    user_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission(
            "DEACTIVATE_USER"
        )
    ),
) -> UserListItem:
    """
    Desactiva un usuario y registra auditoría
    de forma atómica.
    """
    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(
            request
        )
        response = supabase.rpc(
            "desactivar_usuario_atomico",
            {
                "p_user_id": str(
                    user_id
                ),
                "p_actor_user_id": str(
                    current_user.id
                ),
                "p_request_id": (
                    context["request_id"]
                ),
                "p_ip_address": (
                    context["ip_address"]
                ),
                "p_user_agent": (
                    context["user_agent"]
                ),
            },
        ).execute()
        resultado = response.data
        if not isinstance(
            resultado,
            dict,
        ):
            raise RuntimeError(
                "Respuesta inválida de "
                "desactivación de usuario."
            )
        if resultado.get("ok") is not True:
            error_code = resultado.get(
                "error_code"
            )
            if error_code == "USER_NOT_FOUND":
                raise HTTPException(
                    status_code=(
                        status.HTTP_404_NOT_FOUND
                    ),
                    detail="Usuario no encontrado.",
                )
            if error_code == "ALREADY_INACTIVE":
                raise HTTPException(
                    status_code=(
                        status.HTTP_400_BAD_REQUEST
                    ),
                    detail=(
                        "El usuario ya se encuentra inactivo."
                    ),
                )
            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
                "FORBIDDEN_SUPERADMIN",
            }:
                raise HTTPException(
                    status_code=(
                        status.HTTP_403_FORBIDDEN
                    ),
                    detail=(
                        "No autorizado para desactivar "
                        "este usuario."
                    ),
                )
            raise RuntimeError(
                "No fue posible desactivar el usuario."
            )
        return _get_user_result(
            supabase,
            user_id=user_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "No fue posible desactivar el usuario."
            ),
        )


# ============================================================
# ELIMINACIÓN DE USUARIO
# ============================================================


@router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        400: {
            "description": (
                "Operación no permitida."
            ),
        },
        401: {
            "description": (
                "No autenticado o sesión inválida."
            ),
        },
        403: {
            "description": (
                "No autorizado para eliminar "
                "este usuario."
            ),
        },
        404: {
            "description": "Usuario no encontrado.",
        },
        500: {
            "description": (
                "Error interno al eliminar el usuario."
            ),
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
    Elimina definitivamente las credenciales de Supabase Auth
    y conserva el registro histórico en public.usuarios.
    FLUJO:
    1. Comprueba si el perfil funcional existe.
    2. Si todavía no está eliminado, ejecuta la RPC que marca
       activo = false, establece deleted_at y registra auditoría.
    3. Elimina definitivamente la identidad de Supabase Auth.
    La separación entre PostgreSQL y Supabase Auth implica que
    no existe una transacción ACID única entre ambos sistemas.
    Si el paso de Auth falla después de confirmar el borrado
    lógico, el endpoint responde 500 y puede reintentarse: al
    detectar deleted_at, omite la RPC y vuelve a intentar Auth.
    """
    supabase = get_supabase_client()

    try:

        # --------------------------------------------------------
        # 1. OBTENER ESTADO ACTUAL DEL USUARIO
        # --------------------------------------------------------
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
            .eq(
                "id",
                str(user_id),
            )
            .maybe_single()
            .execute()
        )
        if not target_response.data:
            raise HTTPException(
                status_code=(
                    status.HTTP_404_NOT_FOUND
                ),
                detail="Usuario no encontrado.",
            )
        target_user = target_response.data
        target_role = target_user.get("roles")
        if user_id == current_user.id:
            raise HTTPException(
                status_code=(
                    status.HTTP_400_BAD_REQUEST
                ),
                detail=(
                    "No puede eliminar "
                    "su propio usuario."
                ),
            )
        if (
            current_user.role_code == "DIRECTIVA"
            and target_role
            and target_role.get("codigo") == "SUPERADMIN"
        ):
            raise HTTPException(
                status_code=(
                    status.HTTP_403_FORBIDDEN
                ),
                detail=(
                    "No autorizado para eliminar "
                    "este usuario."
                ),
            )

        # --------------------------------------------------------
        # 2. BORRADO FUNCIONAL + AUDITORÍA EN POSTGRESQL
        # --------------------------------------------------------
        #
        # Si deleted_at ya existe, significa que una ejecución
        # anterior alcanzó a confirmar PostgreSQL pero pudo haber
        # fallado antes de completar la eliminación en Auth.
        # En ese caso se omite la RPC y se reintenta Auth.
        # --------------------------------------------------------
        if target_user.get("deleted_at") is None:
            context = _request_rpc_context(
                request
            )
            response = supabase.rpc(
                "eliminar_usuario_atomico",
                {
                    "p_user_id": str(
                        user_id
                    ),
                    "p_actor_user_id": str(
                        current_user.id
                    ),
                    "p_request_id": (
                        context["request_id"]
                    ),
                    "p_ip_address": (
                        context["ip_address"]
                    ),
                    "p_user_agent": (
                        context["user_agent"]
                    ),
                },
            ).execute()
            resultado = response.data
            if not isinstance(
                resultado,
                dict,
            ):
                raise RuntimeError(
                    "Respuesta inválida "
                    "de eliminación de usuario."
                )
            if resultado.get("ok") is not True:
                error_code = resultado.get(
                    "error_code"
                )
                if error_code == "USER_NOT_FOUND":
                    raise HTTPException(
                        status_code=(
                            status.HTTP_404_NOT_FOUND
                        ),
                        detail="Usuario no encontrado.",
                    )
                if error_code == "SELF_DELETE":
                    raise HTTPException(
                        status_code=(
                            status.HTTP_400_BAD_REQUEST
                        ),
                        detail=(
                            "No puede eliminar "
                            "su propio usuario."
                        ),
                    )
                if error_code in {
                    "ACTOR_NOT_FOUND",
                    "FORBIDDEN",
                    "FORBIDDEN_SUPERADMIN",
                }:
                    raise HTTPException(
                        status_code=(
                            status.HTTP_403_FORBIDDEN
                        ),
                        detail=(
                            "No autorizado para eliminar "
                            "este usuario."
                        ),
                    )
                raise RuntimeError(
                    "No fue posible completar "
                    "la eliminación funcional del usuario."
                )

        # --------------------------------------------------------
        # 3. ELIMINAR DEFINITIVAMENTE SUPABASE AUTH
        # --------------------------------------------------------
        #
        # should_soft_delete=False realiza eliminación definitiva
        # de la identidad Auth. La auditoría y el registro
        # histórico continúan en public.usuarios.
        # --------------------------------------------------------
        supabase.auth.admin.delete_user(
            str(user_id),
            should_soft_delete=False,
        )
        return None

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=(
                status.HTTP_500_INTERNAL_SERVER_ERROR
            ),
            detail=(
                "El usuario fue eliminado de HuellAPP, "
                "pero no fue posible completar la eliminación "
                "de sus credenciales de autenticación. "
                "Intente nuevamente."
            ),
        )
