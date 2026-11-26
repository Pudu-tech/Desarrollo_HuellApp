"""HuellApp · Coordinadores y monitores por colegio.

RESPONSABILIDADES
------------------------------------------------------------
- Administrar la relación Coordinador <-> Colegio.
- Administrar la relación Coordinador <-> Monitor contextualizada por colegio.
- Exponer la información necesaria para la advertencia de multi-colegio.

SECURITY
------------------------------------------------------------
- Las lecturas exigen permisos RBAC.
- Las escrituras usan RPC SECURITY DEFINER accesibles solo por service_role.
- Las RPC vuelven a validar actor, rol objetivo, colegio y permisos.
"""

from concurrent.futures import ThreadPoolExecutor
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.coordinacion import (
    ColegioReferencia,
    CoordinadorColegioAsignacionRequest,
    CoordinadorColegioItem,
    MonitorCoordinadorAsignacionRequest,
    MonitorCoordinadorItem,
    PanelMonitores,
    UsuarioCoordinacionItem,
)


router = APIRouter(
    prefix="/colegios/{colegio_id}/coordinadores",
    tags=["Coordinación por colegio"],
)


def _rpc_context(request: Request) -> dict:
    """Obtiene metadatos de auditoría comunes a las escrituras."""

    request_id_raw = getattr(request.state, "request_id", None)
    return {
        "request_id": str(request_id_raw) if request_id_raw is not None else None,
        "ip_address": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
    }


def _obtener_colegio(supabase, colegio_id: UUID, *, coordinador_id: UUID | None = None) -> dict:
    """Valida que el colegio exista y no esté eliminado."""

    fields = "id,nombre,activo"
    if coordinador_id is not None:
        fields += ",coordinacion:usuario_colegio!colegio_id(id)"
    query = (
        supabase.table("colegios")
        .select(fields)
        .eq("id", str(colegio_id))
        .is_("deleted_at", "null")
        .limit(1)
    )
    if coordinador_id is not None:
        query = query.eq("coordinacion.usuario_id", str(coordinador_id)).eq("coordinacion.activo", True)
    response = query.execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Colegio no encontrado.")
    colegio = response.data[0]
    if coordinador_id is not None and not colegio["coordinacion"]:
        raise HTTPException(status_code=403, detail="El coordinador no está asignado a este colegio.")
    return colegio




def _listar_usuarios_activos_por_rol(supabase, role_code: str) -> list[UsuarioCoordinacionItem]:
    """Lista candidatos activos de un rol sin exponer datos administrativos innecesarios."""

    response = (
        supabase.table("usuarios")
        .select("id,nombres,apellido_paterno,apellido_materno,email,roles!inner(codigo)")
        .eq("roles.codigo", role_code)
        .eq("activo", True)
        .is_("deleted_at", "null")
        .execute()
    )
    items: list[UsuarioCoordinacionItem] = []
    for row in response.data or []:
        items.append(
            UsuarioCoordinacionItem(
                id=row["id"],
                nombres=row["nombres"],
                apellido_paterno=row["apellido_paterno"],
                apellido_materno=row.get("apellido_materno"),
                email=row["email"],
            )
        )
    items.sort(key=lambda item: (item.apellido_paterno.lower(), item.nombres.lower()))
    return items


def _validar_coordinador_en_colegio(supabase, coordinador_id: UUID, colegio_id: UUID) -> None:
    """Verifica asociación activa antes de exponer información del equipo."""

    response = (
        supabase.table("usuario_colegio")
        .select("id")
        .eq("usuario_id", str(coordinador_id))
        .eq("colegio_id", str(colegio_id))
        .eq("activo", True)
        .limit(1)
        .execute()
    )
    if not response.data:
        raise HTTPException(status_code=403, detail="El coordinador no está asignado a este colegio.")

def _otros_colegios_coordinadores(
    supabase, coordinador_ids: list[UUID], colegio_id: UUID,
) -> dict[str, list[ColegioReferencia]]:
    """Lista otros colegios activos del coordinador para informar excepciones."""

    if not coordinador_ids:
        return {}
    response = (
        supabase.table("usuario_colegio")
        .select("usuario_id,colegios!colegio_id(id,nombre,activo,deleted_at)")
        .in_("usuario_id", [str(coordinador_id) for coordinador_id in coordinador_ids])
        .eq("activo", True)
        .neq("colegio_id", str(colegio_id))
        .execute()
    )

    colegios: dict[str, list[ColegioReferencia]] = {}
    for item in response.data or []:
        colegio = item.get("colegios") or {}
        if colegio.get("activo") is True and colegio.get("deleted_at") is None:
            colegios.setdefault(str(item["usuario_id"]), []).append(
                ColegioReferencia(
                    id=colegio["id"],
                    nombre=colegio["nombre"],
                )
            )
    return colegios


def _obtener_coordinador_item(supabase, colegio_id: UUID, coordinador_id: UUID) -> CoordinadorColegioItem:
    """Recupera una asociación vigente o inactiva del coordinador con el colegio."""

    relation = (
        supabase.table("usuario_colegio")
        .select("id,activo,usuario:usuarios!usuario_id(id,nombres,apellido_paterno,apellido_materno,email)")
        .eq("usuario_id", str(coordinador_id))
        .eq("colegio_id", str(colegio_id))
        .limit(1)
        .execute()
    )
    if not relation.data:
        raise HTTPException(status_code=404, detail="Coordinador no asignado al colegio.")

    row = relation.data[0]
    user = row.get("usuario") or {}
    return CoordinadorColegioItem(
        relation_id=row["id"],
        coordinador_id=user["id"],
        nombres=user["nombres"],
        apellido_paterno=user["apellido_paterno"],
        apellido_materno=user.get("apellido_materno"),
        email=user["email"],
        activo=row["activo"],
        otros_colegios=_otros_colegios_coordinadores(supabase, [coordinador_id], colegio_id).get(str(coordinador_id), []),
    )


def _gestionar_coordinador(
    request: Request,
    *,
    accion: str,
    colegio_id: UUID,
    coordinador_id: UUID,
    confirmar_multi_colegio: bool,
    actor: AuthenticatedUser,
) -> dict:
    """Ejecuta la asociación coordinador-colegio con auditoría atómica."""

    supabase = get_supabase_client()
    context = _rpc_context(request)
    try:
        result = supabase.rpc(
            "gestionar_coordinador_colegio_atomico",
            {
                "p_accion": accion,
                "p_colegio_id": str(colegio_id),
                "p_coordinador_id": str(coordinador_id),
                "p_confirmar_multi_colegio": confirmar_multi_colegio,
                "p_actor_user_id": str(actor.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute().data
    except Exception as exc:
        raise HTTPException(status_code=500, detail="No fue posible gestionar el coordinador.") from exc

    if not isinstance(result, dict):
        raise HTTPException(status_code=500, detail="Respuesta inválida al gestionar el coordinador.")
    if result.get("ok") is True:
        return result

    code = result.get("error_code")
    if code == "MULTI_SCHOOL_CONFIRMATION_REQUIRED":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": code,
                "message": "Este coordinador ya está asignado a otro colegio. Confirma la asignación excepcional para continuar.",
                "colegios": result.get("colegios") or [],
            },
        )

    errors = {
        "ACTOR_NOT_FOUND": (403, "Usuario autenticado no disponible."),
        "FORBIDDEN": (403, "Sin permisos para gestionar coordinadores."),
        "SCHOOL_NOT_FOUND": (404, "Colegio no encontrado."),
        "SCHOOL_INACTIVE": (409, "No se puede asignar un coordinador a un colegio inactivo."),
        "COORDINATOR_NOT_FOUND": (404, "Coordinador no encontrado."),
        "INVALID_COORDINATOR": (422, "El usuario seleccionado no es un coordinador activo."),
        "RELATION_NOT_FOUND": (404, "El coordinador no está asignado activamente a este colegio."),
        "INVALID_ACTION": (400, "Operación no reconocida."),
    }
    http_code, message = errors.get(code, (500, "Error al gestionar el coordinador."))
    raise HTTPException(status_code=http_code, detail=message)


def _gestionar_monitor(
    request: Request,
    *,
    accion: str,
    colegio_id: UUID,
    coordinador_id: UUID,
    monitor_id: UUID,
    actor: AuthenticatedUser,
) -> None:
    """Ejecuta la asociación monitor-coordinador/colegio con auditoría atómica."""

    supabase = get_supabase_client()
    context = _rpc_context(request)
    try:
        result = supabase.rpc(
            "gestionar_coordinador_monitor_atomico",
            {
                "p_accion": accion,
                "p_colegio_id": str(colegio_id),
                "p_coordinador_id": str(coordinador_id),
                "p_monitor_id": str(monitor_id),
                "p_actor_user_id": str(actor.id),
                "p_request_id": context["request_id"],
                "p_ip_address": context["ip_address"],
                "p_user_agent": context["user_agent"],
            },
        ).execute().data
    except Exception as exc:
        raise HTTPException(status_code=500, detail="No fue posible gestionar el monitor.") from exc

    if not isinstance(result, dict):
        raise HTTPException(status_code=500, detail="Respuesta inválida al gestionar el monitor.")
    if result.get("ok") is True:
        return

    errors = {
        "ACTOR_NOT_FOUND": (403, "Usuario autenticado no disponible."),
        "FORBIDDEN": (403, "Sin permisos para gestionar monitores."),
        "SCHOOL_NOT_FOUND": (404, "Colegio no encontrado o inactivo."),
        "INVALID_COORDINATOR": (422, "El usuario seleccionado no es un coordinador activo."),
        "COORDINATOR_NOT_ASSIGNED_TO_SCHOOL": (409, "El coordinador no está asignado activamente a este colegio."),
        "INVALID_MONITOR": (422, "El usuario seleccionado no es un monitor activo."),
        "RELATION_NOT_FOUND": (404, "El monitor no está asignado activamente a este coordinador."),
        "INVALID_ACTION": (400, "Operación no reconocida."),
    }
    http_code, message = errors.get(result.get("error_code"), (500, "Error al gestionar el monitor."))
    raise HTTPException(status_code=http_code, detail=message)


@router.get("", response_model=list[CoordinadorColegioItem])
def listar_coordinadores_colegio(
    colegio_id: UUID,
    incluir_inactivos: bool = False,
    actor: AuthenticatedUser = Depends(require_permission("VIEW_SCHOOL_COORDINATORS")),
) -> list[CoordinadorColegioItem]:
    """Lista coordinadores asociados al colegio y sus otros colegios activos."""

    supabase = get_supabase_client()
    _obtener_colegio(supabase, colegio_id)

    if incluir_inactivos and actor.role_code not in {"SUPERADMIN", "DIRECTIVA"}:
        raise HTTPException(status_code=403, detail="No puede consultar asociaciones inactivas.")

    query = (
        supabase.table("usuario_colegio")
        .select("id,usuario_id,activo,usuario:usuarios!usuario_id(id,nombres,apellido_paterno,apellido_materno,email,activo,deleted_at,roles(codigo))")
        .eq("colegio_id", str(colegio_id))
    )
    if not incluir_inactivos:
        query = query.eq("activo", True)

    response = query.execute()
    items: list[CoordinadorColegioItem] = []
    for row in response.data or []:
        user = row.get("usuario") or {}
        role = user.get("roles") or {}
        if role.get("codigo") != "COORDINADOR" or user.get("deleted_at") is not None:
            continue
        items.append(
            CoordinadorColegioItem(
                relation_id=row["id"],
                coordinador_id=user["id"],
                nombres=user["nombres"],
                apellido_paterno=user["apellido_paterno"],
                apellido_materno=user.get("apellido_materno"),
                email=user["email"],
                activo=row["activo"],
            )
        )

    otros_colegios = _otros_colegios_coordinadores(supabase, [item.coordinador_id for item in items], colegio_id)
    for item in items:
        item.otros_colegios = otros_colegios.get(str(item.coordinador_id), [])
    items.sort(key=lambda item: (item.apellido_paterno.lower(), item.nombres.lower()))
    return items


@router.get("/candidatos", response_model=list[UsuarioCoordinacionItem])
def listar_coordinadores_candidatos(
    colegio_id: UUID,
    actor: AuthenticatedUser = Depends(require_permission("MANAGE_SCHOOL_COORDINATORS")),
) -> list[UsuarioCoordinacionItem]:
    """Lista coordinadores activos elegibles para asociar al establecimiento."""

    supabase = get_supabase_client()
    _obtener_colegio(supabase, colegio_id)
    return _listar_usuarios_activos_por_rol(supabase, "COORDINADOR")


@router.post("", response_model=CoordinadorColegioItem, status_code=status.HTTP_201_CREATED)
def asignar_coordinador_colegio(
    request: Request,
    colegio_id: UUID,
    payload: CoordinadorColegioAsignacionRequest,
    actor: AuthenticatedUser = Depends(require_permission("MANAGE_SCHOOL_COORDINATORS")),
) -> CoordinadorColegioItem:
    """Asigna un coordinador; exige confirmación si ya trabaja en otro colegio."""

    _gestionar_coordinador(
        request,
        accion="ASSIGN",
        colegio_id=colegio_id,
        coordinador_id=payload.coordinador_id,
        confirmar_multi_colegio=payload.confirmar_multi_colegio,
        actor=actor,
    )
    return _obtener_coordinador_item(get_supabase_client(), colegio_id, payload.coordinador_id)


@router.delete("/{coordinador_id}", status_code=status.HTTP_204_NO_CONTENT)
def desasignar_coordinador_colegio(
    request: Request,
    colegio_id: UUID,
    coordinador_id: UUID,
    actor: AuthenticatedUser = Depends(require_permission("MANAGE_SCHOOL_COORDINATORS")),
) -> None:
    """Desactiva la relación y sus monitores asociados en este colegio."""

    _gestionar_coordinador(
        request,
        accion="UNASSIGN",
        colegio_id=colegio_id,
        coordinador_id=coordinador_id,
        confirmar_multi_colegio=True,
        actor=actor,
    )


@router.get("/{coordinador_id}/monitores", response_model=list[MonitorCoordinadorItem])
def listar_monitores_coordinador(
    colegio_id: UUID,
    coordinador_id: UUID,
    incluir_inactivos: bool = False,
    actor: AuthenticatedUser = Depends(require_permission("VIEW_COORDINATOR_MONITORS")),
) -> list[MonitorCoordinadorItem]:
    """Lista los monitores del coordinador dentro de un colegio concreto."""

    supabase = get_supabase_client()
    _obtener_colegio(supabase, colegio_id)

    if actor.role_code == "COORDINADOR":
        if actor.id != coordinador_id:
            raise HTTPException(status_code=403, detail="Solo puede consultar sus propios monitores.")
        _validar_coordinador_en_colegio(supabase, coordinador_id, colegio_id)
    if incluir_inactivos and actor.role_code not in {"SUPERADMIN", "DIRECTIVA"}:
        raise HTTPException(status_code=403, detail="No puede consultar asociaciones inactivas.")

    return _consultar_monitores(supabase, colegio_id, coordinador_id, incluir_inactivos=incluir_inactivos)


def _consultar_monitores(
    supabase, colegio_id: UUID, coordinador_id: UUID, *,
    incluir_inactivos: bool = False, monitor_id: UUID | None = None,
) -> list[MonitorCoordinadorItem]:
    query = (
        supabase.table("coordinador_monitor_colegio")
        .select("id,monitor_id,activo,monitor:usuarios!fk_cmc_monitor(id,nombres,apellido_paterno,apellido_materno,email,deleted_at)")
        .eq("colegio_id", str(colegio_id))
        .eq("coordinador_id", str(coordinador_id))
    )
    if not incluir_inactivos:
        query = query.eq("activo", True)
    if monitor_id is not None:
        query = query.eq("monitor_id", str(monitor_id))

    response = query.execute()
    items: list[MonitorCoordinadorItem] = []
    for row in response.data or []:
        monitor = row.get("monitor") or {}
        if not monitor or monitor.get("deleted_at") is not None:
            continue
        items.append(
            MonitorCoordinadorItem(
                relation_id=row["id"],
                monitor_id=monitor["id"],
                nombres=monitor["nombres"],
                apellido_paterno=monitor["apellido_paterno"],
                apellido_materno=monitor.get("apellido_materno"),
                email=monitor["email"],
                activo=row["activo"],
            )
        )

    items.sort(key=lambda item: (item.apellido_paterno.lower(), item.nombres.lower()))
    return items


@router.get("/{coordinador_id}/monitores/panel", response_model=PanelMonitores)
def panel_monitores(
    colegio_id: UUID,
    coordinador_id: UUID,
    actor: AuthenticatedUser = Depends(require_permission("VIEW_COORDINATOR_MONITORS")),
) -> PanelMonitores:
    """Carga asignados y candidatos mediante una sola petición autenticada."""
    if actor.role_code == "COORDINADOR" and actor.id != coordinador_id:
        raise HTTPException(status_code=403, detail="Solo puede consultar sus propios monitores.")
    supabase = get_supabase_client()
    puede_gestionar = "MANAGE_COORDINATOR_MONITORS" in actor.effective_permissions
    if puede_gestionar or actor.role_code == "COORDINADOR":
        _obtener_colegio(supabase, colegio_id, coordinador_id=coordinador_id)
    else:
        _obtener_colegio(supabase, colegio_id)
    if not puede_gestionar:
        return PanelMonitores(asignados=_consultar_monitores(supabase, colegio_id, coordinador_id), candidatos=[])
    with ThreadPoolExecutor(max_workers=2) as executor:
        asignados = executor.submit(_consultar_monitores, supabase, colegio_id, coordinador_id)
        candidatos = executor.submit(_listar_usuarios_activos_por_rol, supabase, "MONITOR")
        return PanelMonitores(asignados=asignados.result(), candidatos=candidatos.result())


@router.get("/{coordinador_id}/monitores/candidatos", response_model=list[UsuarioCoordinacionItem])
def listar_monitores_candidatos(
    colegio_id: UUID,
    coordinador_id: UUID,
    actor: AuthenticatedUser = Depends(require_permission("MANAGE_COORDINATOR_MONITORS")),
) -> list[UsuarioCoordinacionItem]:
    """Lista monitores activos elegibles para el coordinador en este colegio."""

    supabase = get_supabase_client()
    _obtener_colegio(supabase, colegio_id)
    _validar_coordinador_en_colegio(supabase, coordinador_id, colegio_id)
    return _listar_usuarios_activos_por_rol(supabase, "MONITOR")


@router.post("/{coordinador_id}/monitores", response_model=MonitorCoordinadorItem, status_code=status.HTTP_201_CREATED)
def asignar_monitor_coordinador(
    request: Request,
    colegio_id: UUID,
    coordinador_id: UUID,
    payload: MonitorCoordinadorAsignacionRequest,
    actor: AuthenticatedUser = Depends(require_permission("MANAGE_COORDINATOR_MONITORS")),
) -> MonitorCoordinadorItem:
    """Asocia un monitor al coordinador en el contexto del colegio."""

    _gestionar_monitor(
        request,
        accion="ASSIGN",
        colegio_id=colegio_id,
        coordinador_id=coordinador_id,
        monitor_id=payload.monitor_id,
        actor=actor,
    )

    items = _consultar_monitores(
        get_supabase_client(), colegio_id, coordinador_id, monitor_id=payload.monitor_id,
    )
    if items:
        return items[0]
    raise HTTPException(status_code=500, detail="No fue posible recuperar el monitor asignado.")


@router.delete("/{coordinador_id}/monitores/{monitor_id}", status_code=status.HTTP_204_NO_CONTENT)
def desasignar_monitor_coordinador(
    request: Request,
    colegio_id: UUID,
    coordinador_id: UUID,
    monitor_id: UUID,
    actor: AuthenticatedUser = Depends(require_permission("MANAGE_COORDINATOR_MONITORS")),
) -> None:
    """Desactiva la asociación monitor-coordinador conservando historial."""

    _gestionar_monitor(
        request,
        accion="UNASSIGN",
        colegio_id=colegio_id,
        coordinador_id=coordinador_id,
        monitor_id=monitor_id,
        actor=actor,
    )
