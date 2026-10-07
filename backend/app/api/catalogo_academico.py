"""Catálogo transversal con permisos efectivos y escrituras RPC auditadas.

No permite borrado físico, traslado de espacios ni estado/actor enviados por UI.
Las comprobaciones de concurrencia y asignaciones vigentes ocurren en PostgreSQL.
"""
from typing import Literal
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Request
from app.core.security import get_current_user, require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.catalogo_academico import CatalogoAcademico, RecursoAcademicoDatos, RecursoAcademicoItem
from app.api.salas import _request_rpc_context

router = APIRouter(prefix="/catalogo-academico", tags=["Catálogo académico"])
Entidad = Literal["asignaturas", "reflexion", "encuentro"]
ENTIDADES = {"asignaturas": "SUBJECT", "reflexion": "REFLECTION_SPACE", "encuentro": "ENCOUNTER_SPACE"}


def proyectar_ramo(row: dict) -> dict:
    """La relación explícita reemplaza el antiguo nivel único sin cambiar IDs."""
    return {**row, "nivel_ids": [item["nivel_curso_id"] for item in row.get("ramo_nivel", [])]}


@router.get("", response_model=CatalogoAcademico)
async def consultar_catalogo(_actor: AuthenticatedUser = Depends(require_permission("VIEW_ACADEMIC_CATALOG"))):
    try:
        db = get_supabase_client()
        def recursos(table, extra=""):
            return db.table(table).select("id,nombre,descripcion,activo" + extra).is_("deleted_at", "null").order("nombre").execute().data or []
        return CatalogoAcademico.model_validate({
            "niveles": db.table("niveles_curso").select("id,nombre,activo").order("orden").execute().data or [],
            "asignaturas": [proyectar_ramo(row) for row in recursos("ramos", ",ramo_nivel(nivel_curso_id)")],
            "reflexion": recursos("espacios_reflexion", ",ramo_id,orden"),
            "encuentro": recursos("espacios_encuentro", ",ramo_id,orden"),
        })
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar el catálogo académico. Verifica que la migración 046 esté aplicada.") from exc


def ejecutar_operacion(entidad, accion, registro_id, datos, actor, request):
    """El RPC verifica de nuevo actor y permiso dentro de la transacción."""
    try:
        if datos and (entidad == "asignaturas") != (datos.nivel_ids is not None):
            raise HTTPException(422, "Los campos no corresponden al tipo de recurso seleccionado.")
        context = _request_rpc_context(request)
        payload = datos.model_dump(mode="json", exclude_none=True) if datos else {}
        # Null explícito permite limpiar campos opcionales durante la edición.
        if datos:
            payload["descripcion"] = datos.descripcion
            if entidad != "asignaturas":
                payload["orden"] = datos.orden
        result = get_supabase_client().rpc("gestionar_catalogo_academico_atomico", {
            "p_entidad": ENTIDADES[entidad], "p_accion": accion, "p_id": str(registro_id) if registro_id else None,
            "p_datos": payload, "p_actor_user_id": str(actor.id),
            **{f"p_{key}": value for key, value in context.items()},
        }).execute().data
        if not isinstance(result, dict):
            raise RuntimeError("Respuesta RPC inválida")
        if result.get("ok") is not True:
            code = result.get("error_code")
            errors = {
                "FORBIDDEN": (403, "No posee permiso para esta operación."),
                "ACTOR_NOT_FOUND": (403, "El usuario no está disponible."),
                "NOT_FOUND": (404, "Recurso inexistente o eliminado."),
                "HAS_FUTURE_ASSIGNMENTS": (409, "Hay asignaciones vigentes desde hoy. Cancélalas o reasígnalas antes de retirar este recurso o nivel."),
                "PARENT_UNAVAILABLE": (409, "La asignatura debe estar activa para administrar sus espacios."),
                "PARENT_IMMUTABLE": (409, "Un espacio conserva su asignatura original."),
                "INVALID_LEVELS": (422, "Selecciona al menos un nivel activo."),
                "INVALID_DATA": (422, "Los datos del catálogo no son válidos."),
            }
            if code in errors:
                raise HTTPException(*errors[code])
            raise RuntimeError("Error RPC")
        return RecursoAcademicoItem.model_validate(result["registro"])
    except HTTPException:
        raise
    except Exception as exc:
        if "23505" in str(exc) or "ACADEMIC_NAME_EXISTS" in str(exc):
            raise HTTPException(409, "Ya existe una asignatura con ese nombre, o un espacio con ese nombre dentro de la asignatura.") from exc
        if "ACADEMIC_" in str(exc):
            raise HTTPException(409, "El recurso académico cambió o ya no está disponible. Actualiza el catálogo.") from exc
        raise HTTPException(500, "No fue posible guardar el recurso académico.") from exc


@router.post("/{entidad}", response_model=RecursoAcademicoItem, status_code=201)
async def crear_recurso(entidad: Entidad, datos: RecursoAcademicoDatos, request: Request,
                        actor: AuthenticatedUser = Depends(require_permission("CREATE_ACADEMIC_CATALOG"))):
    return ejecutar_operacion(entidad, "CREATE", None, datos, actor, request)


@router.put("/{entidad}/{registro_id}", response_model=RecursoAcademicoItem)
async def editar_recurso(entidad: Entidad, registro_id: UUID, datos: RecursoAcademicoDatos, request: Request,
                         actor: AuthenticatedUser = Depends(require_permission("UPDATE_ACADEMIC_CATALOG"))):
    return ejecutar_operacion(entidad, "UPDATE", registro_id, datos, actor, request)


@router.patch("/{entidad}/{registro_id}/{accion}", response_model=RecursoAcademicoItem)
async def cambiar_estado(entidad: Entidad, registro_id: UUID, accion: Literal["activate", "deactivate"], request: Request,
                         actor: AuthenticatedUser = Depends(get_current_user)):
    # Dependencia parametrizada: usa exactamente el permiso de la acción solicitada.
    await require_permission(accion.upper() + "_ACADEMIC_CATALOG")(actor)
    return ejecutar_operacion(entidad, accion.upper(), registro_id, None, actor, request)


@router.delete("/{entidad}/{registro_id}", status_code=204)
async def eliminar_recurso(entidad: Entidad, registro_id: UUID, request: Request,
                          actor: AuthenticatedUser = Depends(require_permission("DELETE_ACADEMIC_CATALOG"))):
    ejecutar_operacion(entidad, "DELETE", registro_id, None, actor, request)
