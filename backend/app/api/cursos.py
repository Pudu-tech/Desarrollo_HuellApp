"""
Endpoints de administración de cursos en HuellAPP.

Funciones disponibles:
- listar cursos;
- obtener curso por UUID;
- crear curso;
- modificar curso;
- activar curso;
- desactivar curso.

SECURITY:
- Todos los endpoints utilizan permisos RBAC.
- created_by y updated_by provienen del usuario autenticado.
- No se confía en colegio_id ni nivel_curso_id sin validarlos.
- nombre_mostrado es generado por backend.
- Las operaciones sensibles quedan registradas en auditoría.
- No existe eliminación física de cursos desde esta API.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.cursos import (
    CursoCreate,
    CursoListItem,
    CursoUpdate,
)


router = APIRouter(
    prefix="/cursos",
    tags=["Cursos"],
)


# ============================================================
# CAMPOS CONSULTADOS
# ============================================================

CURSO_SELECT = """
id,
colegio_id,
nivel_curso_id,
seccion,
nombre_mostrado,
anio,
activo,
created_at,
updated_at
"""


# ============================================================
# FUNCIONES INTERNAS
# ============================================================


def _request_rpc_context(request: Request) -> dict:
    """
    Construye los metadatos comunes enviados a las RPC de escritura.
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


def _obtener_curso_resultado(
    supabase,
    *,
    curso_id: UUID,
) -> CursoListItem:
    """
    Recupera el curso persistido usando el contrato público de respuesta.
    """

    response = (
        supabase.table("cursos_colegio")
        .select(CURSO_SELECT)
        .eq("id", str(curso_id))
        .is_("deleted_at", "null")
        .single()
        .execute()
    )

    return CursoListItem.model_validate(response.data)






def _payload_a_dict(
    payload: CursoCreate | CursoUpdate,
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


def _obtener_colegio_activo(
    supabase,
    *,
    colegio_id: UUID,
) -> dict:
    """
    Valida que un colegio exista, no esté eliminado
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


def _obtener_nivel_activo(
    supabase,
    *,
    nivel_curso_id: UUID,
) -> dict:
    """
    Valida que un nivel de curso exista y se encuentre activo.
    """

    response = (
        supabase.table("niveles_curso")
        .select("id,codigo,nombre,orden,activo")
        .eq("id", str(nivel_curso_id))
        .maybe_single()
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El nivel de curso seleccionado no existe.",
        )

    if response.data["activo"] is not True:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El nivel de curso seleccionado se encuentra inactivo.",
        )

    return response.data






# ============================================================
# LISTAR CURSOS
# ============================================================


@router.get(
    "",
    response_model=list[CursoListItem],
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_COURSES.",
        },
        500: {
            "description": "Error interno al obtener cursos.",
        },
    },
)
async def listar_cursos(
    colegio_id: UUID | None = None,
    nivel_curso_id: UUID | None = None,
    anio: int | None = None,
    activo: bool | None = None,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_COURSES")
    ),
) -> list[CursoListItem]:
    """
    Lista cursos no eliminados lógicamente.

    Filtros opcionales:
    - colegio_id;
    - nivel_curso_id;
    - anio;
    - activo.

    Si no se informa activo, devuelve tanto activos como inactivos.
    """

    supabase = get_supabase_client()

    try:
        query = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT)
            .is_("deleted_at", "null")
        )

        if colegio_id is not None:
            query = query.eq(
                "colegio_id",
                str(colegio_id),
            )

        if nivel_curso_id is not None:
            query = query.eq(
                "nivel_curso_id",
                str(nivel_curso_id),
            )

        if anio is not None:
            if anio < 2000 or anio > 2100:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="El año debe estar entre 2000 y 2100.",
                )

            query = query.eq(
                "anio",
                anio,
            )

        if activo is not None:
            query = query.eq(
                "activo",
                activo,
            )

        response = (
            query
            .order("anio", desc=True)
            .order("nombre_mostrado")
            .execute()
        )

        return [
            CursoListItem.model_validate(item)
            for item in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener los cursos.",
        )


# ============================================================
# OBTENER CURSO
# ============================================================


@router.get(
    "/{curso_id}",
    response_model=CursoListItem,
    responses={
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso VIEW_COURSES.",
        },
        404: {
            "description": "Curso no encontrado.",
        },
        500: {
            "description": "Error interno al obtener el curso.",
        },
    },
)
async def obtener_curso(
    curso_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_COURSES")
    ),
) -> CursoListItem:
    """
    Obtiene un curso no eliminado lógicamente por UUID.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT)
            .eq("id", str(curso_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        return CursoListItem.model_validate(
            response.data
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener el curso.",
        )


# ============================================================
# CREAR CURSO
# ============================================================


@router.post(
    "",
    response_model=CursoListItem,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {"description": "Datos o relaciones inválidas."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso CREATE_COURSE."},
        409: {
            "description": (
                "Ya existe un curso para el mismo colegio, "
                "nivel, sección y año."
            ),
        },
        500: {"description": "Error interno al crear el curso."},
    },
)
async def crear_curso(
    request: Request,
    payload: CursoCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CREATE_COURSE")
    ),
) -> CursoListItem:
    """
    Crea un curso y registra su auditoría en una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        # Las mismas reglas se vuelven a validar dentro de PostgreSQL.
        _obtener_colegio_activo(
            supabase,
            colegio_id=payload.colegio_id,
        )
        _obtener_nivel_activo(
            supabase,
            nivel_curso_id=payload.nivel_curso_id,
        )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "crear_curso_atomico",
            {
                "p_colegio_id": str(payload.colegio_id),
                "p_nivel_curso_id": str(payload.nivel_curso_id),
                "p_seccion": payload.seccion,
                "p_anio": payload.anio,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de creación de curso devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "COURSE_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Ya existe un curso para el mismo colegio, "
                        "nivel, sección y año."
                    ),
                )

            if error_code in {
                "SCHOOL_NOT_ACTIVE",
                "LEVEL_NOT_ACTIVE",
                "INVALID_SECTION",
                "INVALID_YEAR",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos o relaciones del curso no son válidos.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para crear cursos.",
                )

            raise RuntimeError("No fue posible crear el curso.")

        curso_id = resultado.get("curso_id")

        if not curso_id:
            raise RuntimeError("La RPC no devolvió el curso creado.")

        return _obtener_curso_resultado(
            supabase,
            curso_id=UUID(str(curso_id)),
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible crear el curso.",
        )



# ============================================================
# ACTUALIZAR CURSO
# ============================================================


@router.patch(
    "/{curso_id}",
    response_model=CursoListItem,
    responses={
        400: {"description": "Datos inválidos o sin cambios."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso UPDATE_COURSE."},
        404: {"description": "Curso no encontrado."},
        409: {
            "description": (
                "Ya existe un curso para el mismo colegio, "
                "nivel, sección y año."
            ),
        },
        500: {"description": "Error interno al actualizar el curso."},
    },
)
async def actualizar_curso(
    request: Request,
    curso_id: UUID,
    payload: CursoUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_COURSE")
    ),
) -> CursoListItem:
    """
    Actualiza un curso y su auditoría dentro de una sola transacción.
    """

    supabase = get_supabase_client()

    try:
        cambios = _payload_a_dict(payload)

        if not cambios:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se enviaron campos para actualizar.",
            )

        context = _request_rpc_context(request)

        response = supabase.rpc(
            "actualizar_curso_atomico",
            {
                "p_curso_id": str(curso_id),
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
                "La RPC de actualización de curso devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "COURSE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Curso no encontrado.",
                )

            if error_code == "COURSE_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Ya existe un curso para el mismo colegio, "
                        "nivel, sección y año."
                    ),
                )

            if error_code in {
                "NO_CHANGES",
                "INVALID_FIELDS",
                "INVALID_DATA",
                "INVALID_SECTION",
                "INVALID_YEAR",
                "SCHOOL_NOT_ACTIVE",
                "LEVEL_NOT_ACTIVE",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Los datos o relaciones del curso no son válidos.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para actualizar cursos.",
                )

            raise RuntimeError("No fue posible actualizar el curso.")

        return _obtener_curso_resultado(
            supabase,
            curso_id=curso_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar el curso.",
        )



# ============================================================
# ACTIVAR CURSO
# ============================================================


@router.patch(
    "/{curso_id}/activate",
    response_model=CursoListItem,
    responses={
        400: {
            "description": (
                "El curso ya está activo o posee relaciones inválidas."
            ),
        },
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso ACTIVATE_COURSE."},
        404: {"description": "Curso no encontrado."},
        409: {
            "description": (
                "Existe otro curso con la misma combinación académica."
            ),
        },
        500: {"description": "Error interno al activar el curso."},
    },
)
async def activar_curso(
    request: Request,
    curso_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("ACTIVATE_COURSE")
    ),
) -> CursoListItem:
    """
    Activa un curso y registra su auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "activar_curso_atomico",
            {
                "p_curso_id": str(curso_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de activación de curso.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "COURSE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Curso no encontrado.",
                )

            if error_code in {
                "ALREADY_ACTIVE",
                "SCHOOL_NOT_ACTIVE",
                "LEVEL_NOT_ACTIVE",
            }:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El curso ya está activo o posee relaciones inválidas."
                    ),
                )

            if error_code == "COURSE_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Existe otro curso con la misma combinación académica."
                    ),
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para activar cursos.",
                )

            raise RuntimeError("No fue posible activar el curso.")

        return _obtener_curso_resultado(
            supabase,
            curso_id=curso_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible activar el curso.",
        )



# ============================================================
# DESACTIVAR CURSO
# ============================================================


@router.patch(
    "/{curso_id}/deactivate",
    response_model=CursoListItem,
    responses={
        400: {"description": "El curso ya se encuentra inactivo."},
        401: {"description": "No autenticado o sesión inválida."},
        403: {"description": "No posee el permiso DEACTIVATE_COURSE."},
        404: {"description": "Curso no encontrado."},
        500: {"description": "Error interno al desactivar el curso."},
    },
)
async def desactivar_curso(
    request: Request,
    curso_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("DEACTIVATE_COURSE")
    ),
) -> CursoListItem:
    """
    Desactiva un curso y registra su auditoría de forma atómica.
    """

    supabase = get_supabase_client()

    try:
        context = _request_rpc_context(request)

        response = supabase.rpc(
            "desactivar_curso_atomico",
            {
                "p_curso_id": str(curso_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError("Respuesta inválida de desactivación de curso.")

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "COURSE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Curso no encontrado.",
                )

            if error_code == "ALREADY_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El curso ya se encuentra inactivo.",
                )

            if error_code in {"ACTOR_NOT_FOUND", "FORBIDDEN"}:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para desactivar cursos.",
                )

            raise RuntimeError("No fue posible desactivar el curso.")

        return _obtener_curso_resultado(
            supabase,
            curso_id=curso_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar el curso.",
        )

