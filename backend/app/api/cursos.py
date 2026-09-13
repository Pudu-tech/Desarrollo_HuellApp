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
from app.services.audit import write_audit_log


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


def _curso_a_auditoria(
    curso: CursoListItem,
) -> dict:
    """
    Convierte un curso en un diccionario seguro para auditoría.

    Los UUID se convierten a texto para que puedan persistirse
    correctamente en JSONB.
    """

    return {
        "id": str(curso.id),
        "colegio_id": str(curso.colegio_id),
        "nivel_curso_id": str(curso.nivel_curso_id),
        "seccion": curso.seccion,
        "nombre_mostrado": curso.nombre_mostrado,
        "anio": curso.anio,
        "activo": curso.activo,
        "created_at": curso.created_at.isoformat(),
        "updated_at": curso.updated_at.isoformat(),
    }


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


def _validar_duplicado_curso(
    supabase,
    *,
    colegio_id: UUID,
    nivel_curso_id: UUID,
    seccion: str,
    anio: int,
    curso_id_excluir: UUID | None = None,
) -> None:
    """
    Valida la restricción lógica:

    colegio + nivel + sección + año

    La base también posee la restricción UNIQUE:

        uq_curso_colegio_nivel_seccion_anio

    Esta validación permite devolver un error HTTP más claro.
    """

    query = (
        supabase.table("cursos_colegio")
        .select("id")
        .eq("colegio_id", str(colegio_id))
        .eq("nivel_curso_id", str(nivel_curso_id))
        .eq("seccion", seccion)
        .eq("anio", anio)
        .is_("deleted_at", "null")
    )

    if curso_id_excluir is not None:
        query = query.neq(
            "id",
            str(curso_id_excluir),
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
                "Ya existe un curso para el mismo colegio, "
                "nivel, sección y año."
            ),
        )


def _generar_nombre_mostrado(
    *,
    nivel_nombre: str,
    seccion: str,
) -> str:
    """
    Genera el nombre visible del curso.

    Ejemplo:
        nivel_nombre = "7° Básico"
        seccion = "A"

        resultado = "7° Básico A"
    """

    return f"{nivel_nombre} {seccion}"


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
        400: {
            "description": "Datos o relaciones inválidas.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso CREATE_COURSE.",
        },
        409: {
            "description": (
                "Ya existe un curso para el mismo colegio, "
                "nivel, sección y año."
            ),
        },
        500: {
            "description": "Error interno al crear el curso.",
        },
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
    Crea un curso asociado a un colegio.

    Reglas:
    - el colegio debe existir y estar activo;
    - el nivel debe existir y estar activo;
    - sección debe estar entre A y Z;
    - no puede existir otra combinación colegio/nivel/sección/año;
    - nombre_mostrado se genera automáticamente.
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
        # 2. VALIDAR NIVEL
        # --------------------------------------------------------

        nivel = _obtener_nivel_activo(
            supabase,
            nivel_curso_id=payload.nivel_curso_id,
        )

        # --------------------------------------------------------
        # 3. VALIDAR DUPLICADO
        # --------------------------------------------------------

        _validar_duplicado_curso(
            supabase,
            colegio_id=payload.colegio_id,
            nivel_curso_id=payload.nivel_curso_id,
            seccion=payload.seccion,
            anio=payload.anio,
        )

        # --------------------------------------------------------
        # 4. GENERAR NOMBRE MOSTRADO
        # --------------------------------------------------------

        nombre_mostrado = _generar_nombre_mostrado(
            nivel_nombre=nivel["nombre"],
            seccion=payload.seccion,
        )

        # --------------------------------------------------------
        # 5. CREAR CURSO
        # --------------------------------------------------------

        insert_data = _payload_a_dict(payload)

        insert_data["nombre_mostrado"] = nombre_mostrado
        insert_data["activo"] = True
        insert_data["created_by"] = str(current_user.id)
        insert_data["updated_by"] = str(current_user.id)

        insert_response = (
            supabase.table("cursos_colegio")
            .insert(insert_data)
            .execute()
        )

        if not insert_response.data:
            raise RuntimeError(
                "No se creó el curso."
            )

        curso_id = insert_response.data[0]["id"]

        # --------------------------------------------------------
        # 6. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        created_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT)
            .eq("id", curso_id)
            .single()
            .execute()
        )

        curso = CursoListItem.model_validate(
            created_response.data
        )

        # --------------------------------------------------------
        # 7. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="CREATE_COURSE",
            entity_type="COURSE",
            entity_id=curso.id,
            old_values=None,
            new_values=_curso_a_auditoria(curso),
            description="Creación de curso.",
        )

        return curso

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
        400: {
            "description": "Datos inválidos o sin cambios.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso UPDATE_COURSE.",
        },
        404: {
            "description": "Curso no encontrado.",
        },
        409: {
            "description": (
                "Ya existe un curso para el mismo colegio, "
                "nivel, sección y año."
            ),
        },
        500: {
            "description": "Error interno al actualizar el curso.",
        },
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
    Modifica parcialmente un curso.

    Si se cambia el nivel o la sección, nombre_mostrado
    se recalcula automáticamente.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER ESTADO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT + ",deleted_at")
            .eq("id", str(curso_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        curso_actual = CursoListItem.model_validate(
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
                    curso_actual.colegio_id,
                )
            )
        )

        nivel_final = UUID(
            str(
                update_data.get(
                    "nivel_curso_id",
                    curso_actual.nivel_curso_id,
                )
            )
        )

        seccion_final = update_data.get(
            "seccion",
            curso_actual.seccion,
        )

        anio_final = update_data.get(
            "anio",
            curso_actual.anio,
        )

        # --------------------------------------------------------
        # 4. VALIDAR RELACIONES SOLO CUANDO CAMBIAN
        # --------------------------------------------------------

        if "colegio_id" in update_data:
            _obtener_colegio_activo(
                supabase,
                colegio_id=colegio_final,
            )

        nivel = None

        if "nivel_curso_id" in update_data:
            nivel = _obtener_nivel_activo(
                supabase,
                nivel_curso_id=nivel_final,
            )

        # --------------------------------------------------------
        # 5. VALIDAR DUPLICADO FINAL
        # --------------------------------------------------------

        _validar_duplicado_curso(
            supabase,
            colegio_id=colegio_final,
            nivel_curso_id=nivel_final,
            seccion=seccion_final,
            anio=anio_final,
            curso_id_excluir=curso_id,
        )

        # --------------------------------------------------------
        # 6. RECALCULAR NOMBRE MOSTRADO CUANDO CORRESPONDE
        # --------------------------------------------------------

        if (
            "nivel_curso_id" in update_data
            or "seccion" in update_data
        ):
            if nivel is None:
                nivel = _obtener_nivel_activo(
                    supabase,
                    nivel_curso_id=nivel_final,
                )

            update_data["nombre_mostrado"] = (
                _generar_nombre_mostrado(
                    nivel_nombre=nivel["nombre"],
                    seccion=seccion_final,
                )
            )

        # --------------------------------------------------------
        # 7. ACTUALIZAR
        # --------------------------------------------------------

        update_data["updated_by"] = str(current_user.id)

        update_response = (
            supabase.table("cursos_colegio")
            .update(update_data)
            .eq("id", str(curso_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible actualizar el curso."
            )

        # --------------------------------------------------------
        # 8. CONSULTAR ESTADO POSTERIOR
        # --------------------------------------------------------

        updated_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT)
            .eq("id", str(curso_id))
            .single()
            .execute()
        )

        curso_actualizado = CursoListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 9. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="UPDATE_COURSE",
            entity_type="COURSE",
            entity_id=curso_actualizado.id,
            old_values=_curso_a_auditoria(
                curso_actual
            ),
            new_values=_curso_a_auditoria(
                curso_actualizado
            ),
            description="Actualización de curso.",
        )

        return curso_actualizado

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
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso ACTIVATE_COURSE.",
        },
        404: {
            "description": "Curso no encontrado.",
        },
        409: {
            "description": (
                "Existe otro curso con la misma combinación académica."
            ),
        },
        500: {
            "description": "Error interno al activar el curso.",
        },
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
    Reactiva un curso previamente desactivado.

    Antes de activarlo vuelve a validar:
    - colegio activo;
    - nivel activo;
    - ausencia de duplicados.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER CURSO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT + ",deleted_at")
            .eq("id", str(curso_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        curso_actual = CursoListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. VALIDAR ESTADO
        # --------------------------------------------------------

        if curso_actual.activo is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El curso ya se encuentra activo.",
            )

        # --------------------------------------------------------
        # 3. VALIDAR RELACIONES
        # --------------------------------------------------------

        _obtener_colegio_activo(
            supabase,
            colegio_id=curso_actual.colegio_id,
        )

        _obtener_nivel_activo(
            supabase,
            nivel_curso_id=curso_actual.nivel_curso_id,
        )

        # --------------------------------------------------------
        # 4. VALIDAR DUPLICADO
        # --------------------------------------------------------

        _validar_duplicado_curso(
            supabase,
            colegio_id=curso_actual.colegio_id,
            nivel_curso_id=curso_actual.nivel_curso_id,
            seccion=curso_actual.seccion,
            anio=curso_actual.anio,
            curso_id_excluir=curso_id,
        )

        # --------------------------------------------------------
        # 5. ACTIVAR
        # --------------------------------------------------------

        update_response = (
            supabase.table("cursos_colegio")
            .update(
                {
                    "activo": True,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(curso_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible activar el curso."
            )

        # --------------------------------------------------------
        # 6. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        updated_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT)
            .eq("id", str(curso_id))
            .single()
            .execute()
        )

        curso_actualizado = CursoListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 7. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="ACTIVATE_COURSE",
            entity_type="COURSE",
            entity_id=curso_actualizado.id,
            old_values={
                "activo": False,
            },
            new_values={
                "activo": True,
            },
            description="Activación de curso.",
        )

        return curso_actualizado

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
        400: {
            "description": "El curso ya se encuentra inactivo.",
        },
        401: {
            "description": "No autenticado o sesión inválida.",
        },
        403: {
            "description": "No posee el permiso DEACTIVATE_COURSE.",
        },
        404: {
            "description": "Curso no encontrado.",
        },
        500: {
            "description": "Error interno al desactivar el curso.",
        },
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
    Desactiva un curso.

    La operación no elimina físicamente el registro.
    """

    supabase = get_supabase_client()

    try:
        # --------------------------------------------------------
        # 1. OBTENER CURSO ACTUAL
        # --------------------------------------------------------

        current_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT + ",deleted_at")
            .eq("id", str(curso_id))
            .maybe_single()
            .execute()
        )

        if not current_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        if current_response.data.get("deleted_at") is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Curso no encontrado.",
            )

        curso_actual = CursoListItem.model_validate(
            current_response.data
        )

        # --------------------------------------------------------
        # 2. VALIDAR ESTADO
        # --------------------------------------------------------

        if curso_actual.activo is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El curso ya se encuentra inactivo.",
            )

        # --------------------------------------------------------
        # 3. DESACTIVAR
        # --------------------------------------------------------

        update_response = (
            supabase.table("cursos_colegio")
            .update(
                {
                    "activo": False,
                    "updated_by": str(current_user.id),
                }
            )
            .eq("id", str(curso_id))
            .execute()
        )

        if not update_response.data:
            raise RuntimeError(
                "No fue posible desactivar el curso."
            )

        # --------------------------------------------------------
        # 4. CONSULTAR RESULTADO FINAL
        # --------------------------------------------------------

        updated_response = (
            supabase.table("cursos_colegio")
            .select(CURSO_SELECT)
            .eq("id", str(curso_id))
            .single()
            .execute()
        )

        curso_actualizado = CursoListItem.model_validate(
            updated_response.data
        )

        # --------------------------------------------------------
        # 5. AUDITORÍA
        # --------------------------------------------------------

        await write_audit_log(
            request=request,
            actor=current_user,
            action="DEACTIVATE_COURSE",
            entity_type="COURSE",
            entity_id=curso_actualizado.id,
            old_values={
                "activo": True,
            },
            new_values={
                "activo": False,
            },
            description="Desactivación de curso.",
        )

        return curso_actualizado

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible desactivar el curso.",
        )