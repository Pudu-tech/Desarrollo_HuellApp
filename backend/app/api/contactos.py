"""HuellAPP | Administración de personas de contacto de colegios.

REGLAS
------------------------------------------------------------
- Una persona pertenece a un solo colegio; puede reutilizarse en asignaciones.
- Solo se listan contactos no eliminados; los inactivos quedan visibles para gestión.
- Crear/editar/activar/desactivar/eliminar requieren permisos independientes.
- La RPC 043 valida permisos de nuevo y audita cambios atómicamente.
- Nunca se eliminan físicamente contactos ni sus relaciones históricas.
"""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Request, status
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.contactos import ContactoCreate, ContactoItem, ContactoUpdate

router = APIRouter(prefix="/colegios/{colegio_id}/contactos", tags=["Contactos de colegios"])

CAMPOS = "id,colegio_id,nombre,apellido_paterno,apellido_materno,rut,email,telefono,cargo,activo"


def _obtener_contacto(supabase, colegio_id: UUID, contacto_id: UUID) -> ContactoItem:
    """Obtiene un contacto vigente del colegio; impide revelar contactos de otros colegios."""
    result = (supabase.table("contactos_colegio").select(CAMPOS)
              .eq("id", str(contacto_id)).eq("colegio_id", str(colegio_id))
              .is_("deleted_at", "null").limit(1).execute())
    if not result.data:
        raise HTTPException(status_code=404, detail="Contacto no encontrado.")
    return ContactoItem.model_validate(result.data[0])


def _gestionar(request: Request, accion: str, colegio_id: UUID,
              actor: AuthenticatedUser, contacto_id: UUID | None = None,
              datos: dict | None = None) -> UUID:
    """Ejecuta una única RPC: edición y auditoría nunca quedan desincronizadas."""
    supabase = get_supabase_client()
    try:
        result = supabase.rpc("gestionar_contacto_colegio_atomico", {
            "p_accion": accion,
            "p_colegio_id": str(colegio_id),
            "p_contacto_id": str(contacto_id) if contacto_id else None,
            "p_datos": datos,
            "p_actor_user_id": str(actor.id),
            "p_request_id": str(getattr(request.state, "request_id", None)) if getattr(request.state, "request_id", None) else None,
            "p_ip_address": request.client.host if request.client else None,
            "p_user_agent": request.headers.get("user-agent"),
        }).execute().data
    except Exception as exc:
        raise HTTPException(status_code=500, detail="No fue posible procesar el contacto.") from exc

    if not isinstance(result, dict):
        raise HTTPException(status_code=500, detail="Respuesta inválida al gestionar contacto.")
    if result.get("ok") is not True:
        code = result.get("error_code")
        errors = {
            "ACTOR_NOT_FOUND": (403, "Usuario no disponible."),
            "FORBIDDEN": (403, "Sin permisos para esta operación."),
            "SCHOOL_NOT_FOUND": (404, "Colegio no encontrado."),
            "CONTACT_NOT_FOUND": (404, "Contacto no encontrado."),
            "SCHOOL_INACTIVE": (409, "No se pueden incorporar o activar contactos en un colegio inactivo."),
            "CONTACT_HAS_FUTURE_ASSIGNMENTS": (409, "El contacto tiene asignaciones futuras vigentes; reasigna antes de continuar."),
            "REQUIRED_FIELDS": (422, "Nombre, correo y teléfono son obligatorios."),
            "INVALID_DATA": (422, "Datos del contacto inválidos."),
            "INVALID_ACTION": (400, "Operación no reconocida."),
        }
        http_code, message = errors.get(code, (500, "Error al gestionar contacto."))
        raise HTTPException(status_code=http_code, detail=message)
    return UUID(result["contacto_id"])


@router.get("", response_model=list[ContactoItem])
def listar_contactos(colegio_id: UUID, incluir_inactivos: bool = False,
                           _actor: AuthenticatedUser = Depends(require_permission("VIEW_SCHOOL_CONTACTS"))):
    """Lista contactos reutilizables; solo usuarios gestores ven los inactivos."""
    if incluir_inactivos and _actor.role_code not in ("SUPERADMIN", "DIRECTIVA"):
        raise HTTPException(status_code=403, detail="No puede consultar contactos inactivos.")
    supabase = get_supabase_client()
    try:
        school = (supabase.table("colegios").select("id").eq("id", str(colegio_id))
                  .is_("deleted_at", "null").limit(1).execute())
        if not school.data:
            raise HTTPException(status_code=404, detail="Colegio no encontrado.")
        query = (supabase.table("contactos_colegio").select(CAMPOS)
                 .eq("colegio_id", str(colegio_id)).is_("deleted_at", "null"))
        if not incluir_inactivos:
            query = query.eq("activo", True)
        result = query.order("nombre").execute()
        return [ContactoItem.model_validate(item) for item in (result.data or [])]
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail="No fue posible consultar contactos.") from exc


@router.post("", response_model=ContactoItem, status_code=status.HTTP_201_CREATED)
def crear_contacto(request: Request, colegio_id: UUID, payload: ContactoCreate,
                         actor: AuthenticatedUser = Depends(require_permission("CREATE_SCHOOL_CONTACT"))):
    """Crea un contacto y audita el alta en una misma transacción."""
    data = payload.model_dump(mode="json")
    nuevo_id = _gestionar(request, "CREATE", colegio_id, actor, datos=data)
    return _obtener_contacto(get_supabase_client(), colegio_id, nuevo_id)


@router.patch("/{contacto_id}", response_model=ContactoItem)
def editar_contacto(request: Request, colegio_id: UUID, contacto_id: UUID,
                          payload: ContactoUpdate,
                          actor: AuthenticatedUser = Depends(require_permission("UPDATE_SCHOOL_CONTACT"))):
    """Actualiza únicamente los campos enviados por el cliente."""
    if not payload.model_fields_set:
        raise HTTPException(status_code=422, detail="Debes indicar al menos un campo.")
    _gestionar(request, "UPDATE", colegio_id, actor, contacto_id,
              payload.model_dump(exclude_unset=True, mode="json"))
    return _obtener_contacto(get_supabase_client(), colegio_id, contacto_id)


@router.post("/{contacto_id}/activar", response_model=ContactoItem)
def activar_contacto(request: Request, colegio_id: UUID, contacto_id: UUID,
                           actor: AuthenticatedUser = Depends(require_permission("UPDATE_SCHOOL_CONTACT"))):
    """Reactiva un contacto conservando sus relaciones y su UUID."""
    _gestionar(request, "ACTIVATE", colegio_id, actor, contacto_id)
    return _obtener_contacto(get_supabase_client(), colegio_id, contacto_id)


@router.post("/{contacto_id}/desactivar", response_model=ContactoItem)
def desactivar_contacto(request: Request, colegio_id: UUID, contacto_id: UUID,
                              actor: AuthenticatedUser = Depends(require_permission("UPDATE_SCHOOL_CONTACT"))):
    """Desactiva solo si no existen asignaciones futuras vigentes."""
    _gestionar(request, "DEACTIVATE", colegio_id, actor, contacto_id)
    return _obtener_contacto(get_supabase_client(), colegio_id, contacto_id)


@router.delete("/{contacto_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_contacto(request: Request, colegio_id: UUID, contacto_id: UUID,
                            actor: AuthenticatedUser = Depends(require_permission("DELETE_SCHOOL_CONTACT"))):
    """Eliminación lógica restringida; la RPC registra DELETE_SCHOOL_CONTACT."""
    _gestionar(request, "DELETE", colegio_id, actor, contacto_id)
