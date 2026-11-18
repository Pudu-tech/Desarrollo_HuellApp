"""HuellApp · API de catálogos de instancias.

RESPONSABILIDADES
------------------------------------------------------------
- Exponer los endpoints de catálogos de instancias y coordinar consultas, validaciones y respuestas.

ESTADO ACTUAL
------------------------------------------------------------
- Las rutas y dependencias de este módulo definen el contrato HTTP.

SECURITY
------------------------------------------------------------
La autorización se valida en backend con la identidad autenticada.
No se deben confiar roles, actores ni permisos enviados por el navegador.

NOTAS DE IMPLEMENTACIÓN
------------------------------------------------------------
HuellAPP · Consultas para el listado y creación de Instancias.

Reutiliza permisos y validaciones del módulo; no usa VIEW_USERS ni concede
privilegios nuevos. Solo CREATE_ASSIGNMENT permite consultar participantes.
Los catálogos de lectura conservan nombres de colegios eliminados para que
las instancias históricas sigan siendo comprensibles.
"""
from uuid import UUID
from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter, Depends, HTTPException
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.asignacion_catalogos import (
    CatalogosAsignacion, OpcionesCreacionAsignacion,
    OpcionesColegioAsignacion, OpcionesEspaciosAsignacion,
)
from app.api.asignaciones import (
    _obtener_colegio_activo,
    _validar_colegio_coordinador,
    _validar_ramo_activo,
    _validar_permiso_tipo_actividad,
)
from app.api.catalogo_academico import proyectar_ramo

router = APIRouter(prefix="/catalogos/asignaciones", tags=["Catálogos de Instancias"])


def _datos(query) -> list[dict]:
    """Materializa una consulta de lectura; un catálogo vacío es válido."""
    return query.execute().data or []


@router.get("", response_model=CatalogosAsignacion)
def listar_catalogos_asignaciones(
    actor: AuthenticatedUser = Depends(require_permission("VIEW_ASSIGNMENTS")),
) -> CatalogosAsignacion:
    """Consulta nombres para gestión; MONITOR conserva su flujo propio."""
    if actor.role_code == "MONITOR":
        raise HTTPException(403, "Estos catálogos corresponden a la gestión de instancias.")
    try:
        db = get_supabase_client()
        colegios_query = db.table("colegios").select("id,nombre,activo,deleted_at").order("nombre")
        if actor.role_code == "COORDINADOR":
            relaciones = _datos(
                db.table("usuario_colegio")
                .select("colegio_id")
                .eq("usuario_id", str(actor.id))
                .eq("activo", True)
            )
            colegio_ids = [str(item["colegio_id"]) for item in relaciones]
            if not colegio_ids:
                colegios_query = colegios_query.in_("id", ["00000000-0000-0000-0000-000000000000"])
            else:
                colegios_query = colegios_query.in_("id", colegio_ids)

        queries = {
            "tipos_actividad": db.table("tipos_actividad").select("id,codigo,nombre").order("nombre"),
            "estados": db.table("estados_asignacion").select("id,codigo,nombre").order("orden"),
            "colegios": colegios_query,
        }
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {key: executor.submit(_datos, query) for key, query in queries.items()}
            data = {key: future.result() for key, future in futures.items()}
        return CatalogosAsignacion.model_validate(data)
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar los catálogos de instancias.") from exc


@router.get("/creacion", response_model=OpcionesCreacionAsignacion)
def listar_opciones_creacion(
    actor: AuthenticatedUser = Depends(require_permission("CREATE_ASSIGNMENT")),
) -> OpcionesCreacionAsignacion:
    """Entrega opciones de creación filtradas según las actividades permitidas al actor."""
    return _opciones_formulario(actor, filtrar_tipos=True)


@router.get('/reasignacion/participantes')
def opciones_reasignacion(_actor: AuthenticatedUser = Depends(require_permission('REASSIGN_ASSIGNMENT'))):
    """Lista monitores activos disponibles para una reasignación autorizada."""
    rows = _datos(get_supabase_client().table('usuarios').select('id,nombres,apellido_paterno,apellido_materno,roles!inner(codigo)')
                  .eq('activo', True).is_('deleted_at', 'null').eq('roles.codigo', 'MONITOR').order('nombres'))
    return [{key: user.get(key) for key in ('id', 'nombres', 'apellido_paterno', 'apellido_materno')} for user in rows]


@router.get('/gestion-participantes')
def opciones_gestion_participantes(_actor: AuthenticatedUser = Depends(require_permission('REASSIGN_ASSIGNMENT'))):
    """Proyecta personas y tipos elegibles sin habilitar acceso al mantenedor de usuarios."""
    db = get_supabase_client()
    users = _datos(db.table('usuarios').select('id,nombres,apellido_paterno,apellido_materno,roles!inner(codigo)')
                   .eq('activo', True).is_('deleted_at', 'null').in_('roles.codigo', ['DIRECTIVA', 'COORDINADOR', 'MONITOR']).order('nombres'))
    return {
        'participantes': [{key: person.get(key) for key in ('id', 'nombres', 'apellido_paterno', 'apellido_materno')} for person in users],
        'tipos_participacion': _datos(db.table('tipos_participacion').select('id,codigo,nombre').eq('activo', True).order('nombre')),
    }


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
        users_query = (
            db.table("usuarios")
            .select("id,nombres,apellido_paterno,apellido_materno,email,roles!inner(codigo)")
            .eq("activo", True)
            .is_("deleted_at", "null")
            .in_("roles.codigo", ["DIRECTIVA", "COORDINADOR", "MONITOR"])
            .order("nombres")
        )
        users = _datos(users_query)

        # En creación solo se ofrecen monitores. La edición permite además al
        # propio coordinador para conservar participaciones existentes.
        if actor.role_code == "COORDINADOR":
            relaciones = _datos(
                db.table("coordinador_monitor_colegio")
                .select("monitor_id")
                .eq("coordinador_id", str(actor.id))
                .eq("activo", True)
            )
            monitor_ids = {str(item["monitor_id"]) for item in relaciones}
            users = [
                user for user in users
                if (user["roles"]["codigo"] == "MONITOR" and str(user["id"]) in monitor_ids)
                or (not filtrar_tipos and str(user["id"]) == str(actor.id))
            ]
        colegios_query = (
            db.table("colegios")
            .select("id,nombre")
            .eq("activo", True)
            .is_("deleted_at", "null")
            .order("nombre")
        )
        if actor.role_code == "COORDINADOR":
            relaciones = _datos(
                db.table("usuario_colegio")
                .select("colegio_id")
                .eq("usuario_id", str(actor.id))
                .eq("activo", True)
            )
            colegio_ids = [str(item["colegio_id"]) for item in relaciones]
            if colegio_ids:
                colegios_query = colegios_query.in_("id", colegio_ids)
            else:
                colegios_query = colegios_query.in_("id", ["00000000-0000-0000-0000-000000000000"])

        return OpcionesCreacionAsignacion.model_validate({
            "tipos_actividad": allowed,
            "colegios": _datos(colegios_query),
            "participantes": [{**{key: user.get(key) for key in ("id", "nombres", "apellido_paterno", "apellido_materno", "email")},
                                "role_code": user["roles"]["codigo"]} for user in users],
            "tipos_participacion": _datos(db.table("tipos_participacion").select("id,codigo,nombre").eq("activo", True).order("nombre")),
            "ramos": [proyectar_ramo(row) for row in _datos(db.table("ramos").select("id,nombre,nivel_curso_id,ramo_nivel(nivel_curso_id)").eq("activo", True).is_("deleted_at", "null").order("nombre"))],
        })
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar las opciones para crear instancias.") from exc


@router.get("/edicion", response_model=OpcionesCreacionAsignacion)
def opciones_edicion(actor: AuthenticatedUser = Depends(require_permission("UPDATE_ASSIGNMENT"))):
    """El tipo queda fijo al editar; no exige privilegios de creación."""
    return _opciones_formulario(actor, filtrar_tipos=False)


@router.get("/edicion/colegios/{colegio_id}", response_model=OpcionesColegioAsignacion)
def recursos_edicion(colegio_id: UUID, actor: AuthenticatedUser = Depends(require_permission("UPDATE_ASSIGNMENT"))):
    """Reutiliza recursos del colegio bajo el permiso de edición de instancias."""
    return listar_recursos_colegio_asignacion(colegio_id, actor)


@router.get("/edicion/ramos/{ramo_id}/espacios", response_model=OpcionesEspaciosAsignacion)
def espacios_edicion(ramo_id: UUID, actor: AuthenticatedUser = Depends(require_permission("UPDATE_ASSIGNMENT"))):
    """Reutiliza los espacios del ramo bajo el permiso de edición de instancias."""
    return listar_espacios_asignacion(ramo_id, actor)


@router.get("/colegios/{colegio_id}", response_model=OpcionesColegioAsignacion)
def listar_recursos_colegio_asignacion(
    colegio_id: UUID,
    _actor: AuthenticatedUser = Depends(require_permission("CREATE_ASSIGNMENT")),
) -> OpcionesColegioAsignacion:
    """Filtra cursos y contactos por colegio activo; evita mezclar establecimientos."""
    try:
        db = get_supabase_client()
        _obtener_colegio_activo(db, colegio_id=colegio_id)
        if _actor.role_code == "COORDINADOR":
            _validar_colegio_coordinador(
                db,
                coordinador_id=_actor.id,
                colegio_id=colegio_id,
            )
        def recursos(table: str, columns: str, order: str):
            return _datos(db.table(table).select(columns).eq("colegio_id", str(colegio_id))
                          .eq("activo", True).is_("deleted_at", "null").order(order))
        coordinadores_rows = _datos(
            db.table("usuario_colegio")
            .select("usuario_id,usuario:usuarios!usuario_id(id,nombres,apellido_paterno,apellido_materno,activo,deleted_at,roles(codigo))")
            .eq("colegio_id", str(colegio_id))
            .eq("activo", True)
        )
        coordinadores = []
        for row in coordinadores_rows:
            user = row.get("usuario") or {}
            role = user.get("roles") or {}
            if user.get("activo") is not True or user.get("deleted_at") is not None or role.get("codigo") != "COORDINADOR":
                continue
            nombre = " ".join(filter(None, [user.get("nombres"), user.get("apellido_paterno"), user.get("apellido_materno")])).strip()
            coordinadores.append({"id": user.get("id"), "nombre": nombre or "Coordinador"})
        coordinadores.sort(key=lambda item: item["nombre"].casefold())
        coordinadores_visibles = [
            item for item in coordinadores
            if _actor.role_code == "DIRECTIVA"
            or (_actor.role_code == "COORDINADOR" and str(item["id"]) == str(_actor.id))
        ]
        if coordinadores_visibles:
            monitores_por_coordinador = {str(item["id"]): [] for item in coordinadores_visibles}
            relaciones = _datos(
                db.table("coordinador_monitor_colegio")
                .select("coordinador_id,monitor_id")
                .eq("colegio_id", str(colegio_id))
                .eq("activo", True)
                .in_("coordinador_id", list(monitores_por_coordinador))
            )
            for relacion in relaciones:
                monitores_por_coordinador[str(relacion["coordinador_id"])].append(relacion["monitor_id"])
            for coordinador in coordinadores_visibles:
                coordinador["monitor_ids"] = monitores_por_coordinador[str(coordinador["id"])]
        return OpcionesColegioAsignacion.model_validate({
            "cursos": recursos("cursos_colegio", "id,nombre_mostrado,nivel_curso_id,anio", "nombre_mostrado"),
            "contactos": recursos("contactos_colegio", "id,nombre,apellido_paterno,apellido_materno,cargo", "nombre"),
            "coordinadores": coordinadores,
        })
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, "No fue posible cargar los recursos del colegio.") from exc


@router.get("/ramos/{ramo_id}/espacios", response_model=OpcionesEspaciosAsignacion)
def listar_espacios_asignacion(
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
