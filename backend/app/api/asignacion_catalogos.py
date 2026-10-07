"""HuellAPP · Consultas para el listado y creación de Asignaciones.

Reutiliza permisos y validaciones del módulo; no usa VIEW_USERS ni concede
privilegios nuevos. Solo CREATE_ASSIGNMENT permite consultar participantes.
Los catálogos de lectura conservan nombres de colegios eliminados para que
las asignaciones históricas sigan siendo comprensibles.
"""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.asignacion_catalogos import (
    CatalogosAsignacion, OpcionesCreacionAsignacion,
    OpcionesColegioAsignacion, OpcionesEspaciosAsignacion,
)
from app.api.asignaciones import (
    _obtener_colegio_activo, _validar_ramo_activo, _validar_permiso_tipo_actividad,
)
from app.api.catalogo_academico import proyectar_ramo

router = APIRouter(prefix="/catalogos/asignaciones", tags=["Catálogos de Asignaciones"])


def _datos(query) -> list[dict]:
    """Materializa una consulta de lectura; un catálogo vacío es válido."""
    return query.execute().data or []


@router.get("", response_model=CatalogosAsignacion)
async def listar_catalogos_asignaciones(
    actor: AuthenticatedUser = Depends(require_permission("VIEW_ASSIGNMENTS")),
) -> CatalogosAsignacion:
    """Consulta nombres para gestión; MONITOR conserva su flujo propio."""
    if actor.role_code == "MONITOR":
        raise HTTPException(403, "Estos catálogos corresponden a la gestión de asignaciones.")
    try:
        db = get_supabase_client()
        return CatalogosAsignacion.model_validate({
            "tipos_actividad": _datos(db.table("tipos_actividad").select("id,codigo,nombre").order("nombre")),
            "estados": _datos(db.table("estados_asignacion").select("id,codigo,nombre").order("orden")),
            "colegios": _datos(db.table("colegios").select("id,nombre").order("nombre")),
        })
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar los catálogos de asignaciones.") from exc


@router.get("/creacion", response_model=OpcionesCreacionAsignacion)
async def listar_opciones_creacion(
    actor: AuthenticatedUser = Depends(require_permission("CREATE_ASSIGNMENT")),
) -> OpcionesCreacionAsignacion:
    return _opciones_formulario(actor, filtrar_tipos=True)


def _opciones_formulario(actor: AuthenticatedUser, filtrar_tipos: bool) -> OpcionesCreacionAsignacion:
    """Ofrece actividades permitidas y participantes activos, excluyendo SUPERADMIN."""
    try:
        db = get_supabase_client()
        types = _datos(db.table("tipos_actividad").select("id,codigo,nombre").eq("activo", True).order("nombre"))
        allowed = []
        for item in types:
            if not filtrar_tipos:
                allowed.append(item)
                continue
            try:
                _validar_permiso_tipo_actividad(db, role_code=actor.role_code, tipo_codigo=item["codigo"])
            except HTTPException as exc:
                if exc.status_code == 403:
                    continue
                raise
            allowed.append(item)
        users = _datos(db.table("usuarios").select("id,nombres,apellido_paterno,apellido_materno,roles!inner(codigo)")
                       .eq("activo", True).is_("deleted_at", "null")
                       .in_("roles.codigo", ["DIRECTIVA", "COORDINADOR", "MONITOR"]).order("nombres")) if filtrar_tipos else []
        return OpcionesCreacionAsignacion.model_validate({
            "tipos_actividad": allowed,
            "colegios": _datos(db.table("colegios").select("id,nombre").eq("activo", True).is_("deleted_at", "null").order("nombre")),
            "participantes": [{**{key: user.get(key) for key in ("id", "nombres", "apellido_paterno", "apellido_materno")},
                                "role_code": user["roles"]["codigo"]} for user in users],
            "tipos_participacion": _datos(db.table("tipos_participacion").select("id,codigo,nombre").eq("activo", True).order("nombre")),
            "ramos": [proyectar_ramo(row) for row in _datos(db.table("ramos").select("id,nombre,nivel_curso_id,ramo_nivel(nivel_curso_id)").eq("activo", True).is_("deleted_at", "null").order("nombre"))],
        })
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar las opciones para crear asignaciones.") from exc


@router.get("/edicion", response_model=OpcionesCreacionAsignacion)
async def opciones_edicion(actor: AuthenticatedUser = Depends(require_permission("UPDATE_ASSIGNMENT"))):
    """El tipo queda fijo al editar; no exige privilegios de creación."""
    return _opciones_formulario(actor, filtrar_tipos=False)


@router.get("/edicion/colegios/{colegio_id}", response_model=OpcionesColegioAsignacion)
async def recursos_edicion(colegio_id: UUID, actor: AuthenticatedUser = Depends(require_permission("UPDATE_ASSIGNMENT"))):
    return await listar_recursos_colegio_asignacion(colegio_id, actor)


@router.get("/edicion/ramos/{ramo_id}/espacios", response_model=OpcionesEspaciosAsignacion)
async def espacios_edicion(ramo_id: UUID, actor: AuthenticatedUser = Depends(require_permission("UPDATE_ASSIGNMENT"))):
    return await listar_espacios_asignacion(ramo_id, actor)


@router.get("/colegios/{colegio_id}", response_model=OpcionesColegioAsignacion)
async def listar_recursos_colegio_asignacion(
    colegio_id: UUID,
    _actor: AuthenticatedUser = Depends(require_permission("CREATE_ASSIGNMENT")),
) -> OpcionesColegioAsignacion:
    """Filtra cursos, salas y contactos por colegio activo; evita mezclar establecimientos."""
    try:
        db = get_supabase_client()
        _obtener_colegio_activo(db, colegio_id=colegio_id)
        def recursos(table: str, columns: str, order: str):
            return _datos(db.table(table).select(columns).eq("colegio_id", str(colegio_id))
                          .eq("activo", True).is_("deleted_at", "null").order(order))
        return OpcionesColegioAsignacion.model_validate({
            "cursos": recursos("cursos_colegio", "id,nombre_mostrado,nivel_curso_id,anio", "nombre_mostrado"),
            "salas": recursos("salas", "id,nombre", "nombre"),
            "contactos": recursos("contactos_colegio", "id,nombre,apellido_paterno,apellido_materno,cargo", "nombre"),
        })
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar los recursos del colegio.") from exc


@router.get("/ramos/{ramo_id}/espacios", response_model=OpcionesEspaciosAsignacion)
async def listar_espacios_asignacion(
    ramo_id: UUID,
    _actor: AuthenticatedUser = Depends(require_permission("CREATE_ASSIGNMENT")),
) -> OpcionesEspaciosAsignacion:
    """Los espacios disponibles pertenecen exclusivamente al ramo seleccionado."""
    try:
        db = get_supabase_client()
        _validar_ramo_activo(db, ramo_id=ramo_id)
        def espacios(table: str):
            return _datos(db.table(table).select("id,nombre").eq("ramo_id", str(ramo_id))
                          .eq("activo", True).is_("deleted_at", "null").order("orden").order("nombre"))
        return OpcionesEspaciosAsignacion.model_validate({
            "reflexion": espacios("espacios_reflexion"), "encuentro": espacios("espacios_encuentro"),
        })
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar los espacios del ramo.") from exc
