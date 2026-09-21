"""
Endpoints del módulo de asignaciones de HuellAPP.

FUNCIONES IMPLEMENTADAS:
- listar asignaciones;
- obtener detalle de una asignación;
- crear asignaciones;
- actualizar parcialmente una asignación;
- cancelar asignaciones;
- reabrir asignaciones canceladas;
- agregar participantes;
- quitar participantes mediante soft-delete;
- cambiar tipo de participación;
- reasignar participantes;
- aceptar una participación;
- rechazar una participación;
- reabrir una participación rechazada;
- registrar asistencia propia;
- regularizar asistencia administrativamente.

REGLAS DE SEGURIDAD:
- Todos los endpoints utilizan autenticación y permisos.
- MONITOR solo puede visualizar asignaciones donde figure como participante.
- SUPERADMIN puede administrar asignaciones, pero no participar en ellas.
- Solo el propio participante puede aceptar o rechazar su participación.
- Solo el propio participante puede registrar su propia asistencia.
- Solo participaciones ACEPTADAS pueden registrar o regularizar asistencia.
- SUPERADMIN, DIRECTIVA y COORDINADOR pueden reabrir una participación RECHAZADA.
- La reapertura exige motivo, archiva la participación rechazada y crea una nueva PENDIENTE.
- La asistencia propia requiere geolocalización.
- DIRECTIVA y SUPERADMIN pueden regularizar asistencias mediante
  MANAGE_ATTENDANCE.
- La regularización administrativa no requiere GPS, pero exige
  motivo_regularizacion.
- La gestión administrativa de participantes requiere REASSIGN_ASSIGNMENT.
- CANCEL_ASSIGNMENT permite cancelar a SUPERADMIN, DIRECTIVA y COORDINADOR.
- Solo SUPERADMIN y DIRECTIVA pueden reabrir una asignación CANCELADA.
- Las asignaciones REALIZADAS, CANCELADAS o NO_REALIZADAS no permiten alterar
  participantes mediante el flujo operativo normal.
- El actor siempre se obtiene desde la sesión autenticada.
- Nunca se confía en actor_user_id, respondido_por, informado_por,
  estados iniciales ni campos de auditoría enviados por frontend.

GESTIÓN HISTÓRICA DE PARTICIPANTES:
- quitar un participante NO elimina físicamente el registro;
- se utiliza activo=false + deleted_at;
- la asistencia histórica se conserva;
- reasignar NO modifica usuario_id del registro histórico;
- se archiva la participación anterior y se crea una nueva PENDIENTE;
- cambiar tipo en una participación ya respondida conserva el registro
  anterior y crea uno nuevo PENDIENTE;
- un usuario puede tener registros históricos anteriores, pero solo una
  participación activa por asignación;
- si desaparece el último RELATOR ACEPTADO de una asignación CONFIRMADA,
  la asignación vuelve automáticamente a PENDIENTE.

CICLO DE VIDA:
- una asignación terminada con al menos una asistencia PRESENTE puede pasar
  automáticamente a REALIZADA mediante la lógica central de base de datos;
- después de 24 horas desde hora_fin sin ninguna asistencia PRESENTE puede
  pasar a NO_REALIZADA;
- CANCELADA no participa en ese flujo automático;
- NO_REALIZADA solo puede ser regularizada por DIRECTIVA o SUPERADMIN;
- si una asistencia de una NO_REALIZADA es regularizada a PRESENTE,
  la asignación pasa explícitamente a REALIZADA;
- AUSENTE o JUSTIFICADA no cambian NO_REALIZADA;
- toda regularización de asistencia y cambio global de estado queda auditado.

GEOLOCALIZACIÓN:
El frontend envía únicamente:
- latitud;
- longitud;
- precisión GPS;
- fecha/hora de captura.

Los campos:
- direccion_detectada;
- comuna_detectada;
- region_detectada;

serán calculados posteriormente mediante reverse geocoding desde
el backend.

La ausencia temporal de esos datos legibles NO invalida la asistencia.
Las coordenadas GPS originales son la evidencia principal.

NOTA TRANSACCIONAL:
Los flujos críticos migrados a RPC PostgreSQL se ejecutan de forma atómica.
Los flujos aún no migrados continúan revisándose progresivamente para evitar
estados parciales entre escrituras relacionadas.
"""

from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import ValidationError

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.asignaciones import (
    AsignacionCancelacionRequest,
    AsignacionCreate,
    AsignacionDetail,
    AsignacionListItem,
    AsignacionUpdate,
    AsistenciaPropiaRequest,
    AsistenciaRegularizacionRequest,
    AsistenciaSummary,
    ContactoAsignacionSummary,
    ParticipacionReaperturaRequest,
    ParticipacionRechazoRequest,
    ParticipanteCreate,
    ParticipanteReasignacionRequest,
    ParticipanteSummary,
    ParticipanteTipoUpdateRequest,
)
from app.schemas.auth import AuthenticatedUser



router = APIRouter(
    prefix="/asignaciones",
    tags=["Asignaciones"],
)


# ============================================================
# CAMPOS CONSULTADOS
# ============================================================

ASIGNACION_SELECT = """
id,
tipo_actividad_id,
colegio_id,
curso_colegio_id,
sala_id,
ramo_id,
espacio_reflexion_id,
espacio_encuentro_id,
fecha,
hora_inicio,
hora_fin,
lugar,
observacion,
estado_id,
activo,
created_at,
updated_at
"""


PARTICIPANTE_SELECT = """
id,
usuario_id,
tipo_participacion_id,
estado_participacion_id,
motivo_rechazo,
fecha_respuesta,
respondido_por,
activo
"""


CONTACTO_ASIGNACION_SELECT = """
id,
contacto_colegio_id
"""


ASISTENCIA_SELECT = """
id,
asignacion_participante_id,
estado,
motivo,
motivo_regularizacion,
informado_por,
fecha_informe,
latitud,
longitud,
precision_metros,
direccion_detectada,
comuna_detectada,
region_detectada,
fecha_geolocalizacion,
created_at,
updated_at
"""


# ============================================================
# HELPERS GENERALES
# ============================================================






def _normalizar_asistencia_db(
    asistencia: dict,
) -> dict:
    """
    Traduce las columnas físicas de PostgreSQL al contrato
    público utilizado por la API.

    DB:
        precision_metros

    API:
        precision_gps
    """

    return {
        "id": asistencia["id"],
        "asignacion_participante_id": (
            asistencia["asignacion_participante_id"]
        ),
        "estado": asistencia["estado"],
        "motivo": asistencia.get("motivo"),
        "latitud": asistencia.get("latitud"),
        "longitud": asistencia.get("longitud"),
        "precision_gps": asistencia.get(
            "precision_metros"
        ),
        "fecha_geolocalizacion": asistencia.get(
            "fecha_geolocalizacion"
        ),
        "direccion_detectada": asistencia.get(
            "direccion_detectada"
        ),
        "comuna_detectada": asistencia.get(
            "comuna_detectada"
        ),
        "region_detectada": asistencia.get(
            "region_detectada"
        ),
        "informado_por": asistencia.get(
            "informado_por"
        ),
        "fecha_informe": asistencia.get(
            "fecha_informe"
        ),
        "motivo_regularizacion": asistencia.get(
            "motivo_regularizacion"
        ),
        "created_at": asistencia["created_at"],
        "updated_at": asistencia["updated_at"],
    }


# ============================================================
# PERMISOS
# ============================================================


def _usuario_tiene_permiso(
    supabase,
    *,
    role_code: str,
    permission_code: str,
) -> bool:
    """
    Comprueba si un rol posee un permiso determinado.
    """

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
        .eq("codigo", role_code)
        .eq(
            "rol_permiso.permisos.codigo",
            permission_code,
        )
        .limit(1)
        .execute()
    )

    return bool(response.data)


def _validar_permiso_tipo_actividad(
    supabase,
    *,
    role_code: str,
    tipo_codigo: str,
) -> None:
    """
    Valida permisos especiales por tipo de actividad.
    """

    permiso_especial: str | None = None

    if tipo_codigo == "CAPACITACION":
        permiso_especial = "CREATE_TRAINING"

    elif tipo_codigo == "EVENTO_CASA_CENTRAL":
        permiso_especial = "CREATE_CENTRAL_EVENT"

    if permiso_especial is None:
        return

    if not _usuario_tiene_permiso(
        supabase,
        role_code=role_code,
        permission_code=permiso_especial,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No posee permisos para crear este tipo de actividad.",
        )


# ============================================================
# CATÁLOGOS
# ============================================================


def _obtener_tipo_actividad(
    supabase,
    *,
    tipo_actividad_id: UUID,
) -> dict:
    """
    Obtiene un tipo de actividad activo.
    """

    response = (
        supabase.table("tipos_actividad")
        .select("id,codigo,nombre,activo")
        .eq("id", str(tipo_actividad_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El tipo de actividad seleccionado no existe.",
        )

    tipo = response.data[0]

    if tipo.get("activo") is not True:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El tipo de actividad seleccionado está inactivo.",
        )

    return tipo






def _obtener_codigo_estado_asignacion(
    supabase,
    *,
    estado_id: UUID | str,
) -> str:
    """
    Obtiene código de un estado global.
    """

    response = (
        supabase.table("estados_asignacion")
        .select("codigo")
        .eq("id", str(estado_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise RuntimeError(
            "El estado de la asignación no existe."
        )

    return response.data[0]["codigo"]












# ============================================================
# VALIDACIÓN ACADÉMICA
# ============================================================


def _obtener_colegio_activo(
    supabase,
    *,
    colegio_id: UUID,
) -> dict:
    """
    Valida que un colegio exista y esté activo.
    """

    response = (
        supabase.table("colegios")
        .select("id,nombre,activo,deleted_at")
        .eq("id", str(colegio_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El colegio seleccionado no existe.",
        )

    colegio = response.data[0]

    if colegio.get("deleted_at") is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El colegio seleccionado no existe.",
        )

    if colegio.get("activo") is not True:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El colegio seleccionado se encuentra inactivo.",
        )

    return colegio


def _validar_curso_colegio(
    supabase,
    *,
    curso_id: UUID,
    colegio_id: UUID,
) -> None:
    """
    Valida que el curso exista, esté activo
    y pertenezca al colegio.
    """

    response = (
        supabase.table("cursos_colegio")
        .select("id,colegio_id,activo,deleted_at")
        .eq("id", str(curso_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El curso seleccionado no existe.",
        )

    curso = response.data[0]

    if (
        curso.get("deleted_at") is not None
        or curso.get("activo") is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El curso seleccionado no está disponible.",
        )

    if curso["colegio_id"] != str(colegio_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El curso no pertenece al colegio seleccionado.",
        )


def _validar_sala_colegio(
    supabase,
    *,
    sala_id: UUID,
    colegio_id: UUID,
) -> None:
    """
    Valida que la sala exista, esté activa
    y pertenezca al colegio.
    """

    response = (
        supabase.table("salas")
        .select("id,colegio_id,activo,deleted_at")
        .eq("id", str(sala_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La sala seleccionada no existe.",
        )

    sala = response.data[0]

    if (
        sala.get("deleted_at") is not None
        or sala.get("activo") is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La sala seleccionada no está disponible.",
        )

    if sala["colegio_id"] != str(colegio_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La sala no pertenece al colegio seleccionado.",
        )


def _validar_ramo_activo(
    supabase,
    *,
    ramo_id: UUID,
) -> None:
    """
    Valida que el ramo exista y esté activo.
    """

    response = (
        supabase.table("ramos")
        .select("id,activo,deleted_at")
        .eq("id", str(ramo_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El ramo seleccionado no existe.",
        )

    ramo = response.data[0]

    if (
        ramo.get("deleted_at") is not None
        or ramo.get("activo") is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El ramo seleccionado no está disponible.",
        )


def _validar_espacio_reflexion(
    supabase,
    *,
    espacio_id: UUID,
    ramo_id: UUID,
) -> None:
    """
    Valida un espacio de reflexión.
    """

    response = (
        supabase.table("espacios_reflexion")
        .select("id,ramo_id,activo,deleted_at")
        .eq("id", str(espacio_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El espacio de reflexión seleccionado no existe.",
        )

    espacio = response.data[0]

    if (
        espacio.get("deleted_at") is not None
        or espacio.get("activo") is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El espacio de reflexión no está disponible.",
        )

    if espacio["ramo_id"] != str(ramo_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "El espacio de reflexión no pertenece "
                "al ramo seleccionado."
            ),
        )


def _validar_espacio_encuentro(
    supabase,
    *,
    espacio_id: UUID,
    ramo_id: UUID,
) -> None:
    """
    Valida un espacio de encuentro.
    """

    response = (
        supabase.table("espacios_encuentro")
        .select("id,ramo_id,activo,deleted_at")
        .eq("id", str(espacio_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El espacio de encuentro seleccionado no existe.",
        )

    espacio = response.data[0]

    if (
        espacio.get("deleted_at") is not None
        or espacio.get("activo") is not True
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El espacio de encuentro no está disponible.",
        )

    if espacio["ramo_id"] != str(ramo_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "El espacio de encuentro no pertenece "
                "al ramo seleccionado."
            ),
        )


# ============================================================
# PARTICIPANTES - VALIDACIÓN CREACIÓN
# ============================================================


def _validar_participantes(
    supabase,
    *,
    payload: AsignacionCreate,
) -> None:
    """
    Valida participantes de una asignación nueva.
    """

    for participante in payload.participantes:
        response = (
            supabase.table("usuarios")
            .select(
                """
                id,
                activo,
                deleted_at,
                roles!inner(codigo)
                """
            )
            .eq(
                "id",
                str(participante.usuario_id),
            )
            .limit(1)
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uno de los participantes no existe.",
            )

        usuario = response.data[0]

        if (
            usuario.get("deleted_at") is not None
            or usuario.get("activo") is not True
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uno de los participantes no está disponible.",
            )

        rol = usuario.get(
            "roles",
            {},
        ).get("codigo")

        if rol not in {
            "DIRECTIVA",
            "COORDINADOR",
            "MONITOR",
        }:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Uno de los usuarios seleccionados "
                    "no puede ser participante."
                ),
            )

        tipo_response = (
            supabase.table("tipos_participacion")
            .select("id,activo")
            .eq(
                "id",
                str(
                    participante.tipo_participacion_id
                ),
            )
            .limit(1)
            .execute()
        )

        if (
            not tipo_response.data
            or tipo_response.data[0].get("activo") is not True
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Uno de los tipos de participación "
                    "no existe o está inactivo."
                ),
            )


# ============================================================
# PARTICIPANTES - RESPUESTA
# ============================================================




def _obtener_participacion_actualizada(
    supabase,
    *,
    participante_id: UUID,
) -> ParticipanteSummary:
    """
    Recupera participación actualizada.
    """

    response = (
        supabase.table("asignacion_participantes")
        .select(PARTICIPANTE_SELECT)
        .eq("id", str(participante_id))
        .limit(1)
        .execute()
    )

    if not response.data:
        raise RuntimeError(
            "No fue posible recuperar la participación actualizada."
        )

    return ParticipanteSummary.model_validate(
        response.data[0]
    )


# ============================================================
# CONTACTOS
# ============================================================


def _validar_contactos(
    supabase,
    *,
    payload: AsignacionCreate,
    tipo_codigo: str,
) -> None:
    """
    Valida contactos/profesores.
    """

    tipos_escolares = {
        "ESPACIO_REFLEXION",
        "ESPACIO_ENCUENTRO",
        "REUNION",
    }

    if tipo_codigo in tipos_escolares:
        if len(payload.contactos) < 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "La actividad requiere al menos "
                    "un profesor/contacto."
                ),
            )

        if payload.colegio_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La actividad requiere un colegio.",
            )

        for contacto in payload.contactos:
            response = (
                supabase.table("contactos_colegio")
                .select("id,colegio_id,activo,deleted_at")
                .eq(
                    "id",
                    str(contacto.contacto_colegio_id),
                )
                .limit(1)
                .execute()
            )

            if not response.data:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Uno de los contactos no existe.",
                )

            data = response.data[0]

            if (
                data.get("deleted_at") is not None
                or data.get("activo") is not True
            ):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Uno de los contactos no está disponible.",
                )

            if data["colegio_id"] != str(payload.colegio_id):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "Todos los profesores/contactos deben "
                        "pertenecer al colegio de la asignación."
                    ),
                )

    elif payload.contactos:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Este tipo de actividad no admite "
                "profesores/contactos."
            ),
        )


# ============================================================
# REGLAS POR TIPO
# ============================================================


def _validar_campos_tipo_actividad(
    supabase,
    *,
    payload: AsignacionCreate,
    tipo_codigo: str,
) -> None:
    """
    Valida campos requeridos/prohibidos según tipo.
    """

    if tipo_codigo == "ESPACIO_REFLEXION":
        if (
            payload.colegio_id is None
            or payload.curso_colegio_id is None
            or payload.sala_id is None
            or payload.ramo_id is None
            or payload.espacio_reflexion_id is None
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "ESPACIO_REFLEXION requiere colegio, curso, "
                    "sala, ramo y espacio de reflexión."
                ),
            )

        if (
            payload.espacio_encuentro_id is not None
            or payload.lugar is not None
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "ESPACIO_REFLEXION no admite espacio "
                    "de encuentro ni lugar."
                ),
            )

        _obtener_colegio_activo(
            supabase,
            colegio_id=payload.colegio_id,
        )

        _validar_curso_colegio(
            supabase,
            curso_id=payload.curso_colegio_id,
            colegio_id=payload.colegio_id,
        )

        _validar_sala_colegio(
            supabase,
            sala_id=payload.sala_id,
            colegio_id=payload.colegio_id,
        )

        _validar_ramo_activo(
            supabase,
            ramo_id=payload.ramo_id,
        )

        _validar_espacio_reflexion(
            supabase,
            espacio_id=payload.espacio_reflexion_id,
            ramo_id=payload.ramo_id,
        )

    elif tipo_codigo == "ESPACIO_ENCUENTRO":
        if (
            payload.colegio_id is None
            or payload.curso_colegio_id is None
            or payload.sala_id is None
            or payload.ramo_id is None
            or payload.espacio_encuentro_id is None
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "ESPACIO_ENCUENTRO requiere colegio, curso, "
                    "sala, ramo y espacio de encuentro."
                ),
            )

        if (
            payload.espacio_reflexion_id is not None
            or payload.lugar is not None
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "ESPACIO_ENCUENTRO no admite espacio "
                    "de reflexión ni lugar."
                ),
            )

        _obtener_colegio_activo(
            supabase,
            colegio_id=payload.colegio_id,
        )

        _validar_curso_colegio(
            supabase,
            curso_id=payload.curso_colegio_id,
            colegio_id=payload.colegio_id,
        )

        _validar_sala_colegio(
            supabase,
            sala_id=payload.sala_id,
            colegio_id=payload.colegio_id,
        )

        _validar_ramo_activo(
            supabase,
            ramo_id=payload.ramo_id,
        )

        _validar_espacio_encuentro(
            supabase,
            espacio_id=payload.espacio_encuentro_id,
            ramo_id=payload.ramo_id,
        )

    elif tipo_codigo == "REUNION":
        if payload.colegio_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="REUNION requiere colegio.",
            )

        if (
            payload.ramo_id is not None
            or payload.espacio_reflexion_id is not None
            or payload.espacio_encuentro_id is not None
            or payload.lugar is not None
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "REUNION no admite ramo, espacios "
                    "de reflexión/encuentro ni lugar."
                ),
            )

        _obtener_colegio_activo(
            supabase,
            colegio_id=payload.colegio_id,
        )

        if payload.curso_colegio_id is not None:
            _validar_curso_colegio(
                supabase,
                curso_id=payload.curso_colegio_id,
                colegio_id=payload.colegio_id,
            )

        if payload.sala_id is not None:
            _validar_sala_colegio(
                supabase,
                sala_id=payload.sala_id,
                colegio_id=payload.colegio_id,
            )

    elif tipo_codigo in {
        "CAPACITACION",
        "EVENTO_CASA_CENTRAL",
    }:
        if not payload.lugar:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Este tipo de actividad requiere lugar.",
            )

        if any(
            value is not None
            for value in (
                payload.colegio_id,
                payload.curso_colegio_id,
                payload.sala_id,
                payload.ramo_id,
                payload.espacio_reflexion_id,
                payload.espacio_encuentro_id,
            )
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "CAPACITACION y EVENTO_CASA_CENTRAL "
                    "no admiten datos escolares."
                ),
            )

    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tipo de actividad no soportado.",
        )


# ============================================================
# DETALLE
# ============================================================


def _obtener_detalle_asignacion(
    supabase,
    *,
    asignacion_id: UUID,
) -> AsignacionDetail:
    """
    Construye detalle completo.
    """

    response = (
        supabase.table("asignaciones")
        .select(ASIGNACION_SELECT)
        .eq("id", str(asignacion_id))
        .is_("deleted_at", "null")
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="La asignación no existe.",
        )

    participantes_response = (
        supabase.table("asignacion_participantes")
        .select(PARTICIPANTE_SELECT)
        .eq("asignacion_id", str(asignacion_id))
        .eq("activo", True)
        .is_("deleted_at", "null")
        .execute()
    )

    contactos_response = (
        supabase.table("asignacion_contactos")
        .select(CONTACTO_ASIGNACION_SELECT)
        .eq("asignacion_id", str(asignacion_id))
        .execute()
    )

    return AsignacionDetail.model_validate(
        {
            **response.data[0],
            "participantes": [
                ParticipanteSummary.model_validate(item)
                for item in (participantes_response.data or [])
            ],
            "contactos": [
                ContactoAsignacionSummary.model_validate(item)
                for item in (contactos_response.data or [])
            ],
        }
    )


# ============================================================
# SCOPE MONITOR
# ============================================================


def _obtener_asignaciones_monitor(
    supabase,
    *,
    usuario_id: UUID,
) -> list[str]:
    """
    Obtiene asignaciones donde participa Monitor.
    """

    response = (
        supabase.table("asignacion_participantes")
        .select("asignacion_id")
        .eq("usuario_id", str(usuario_id))
        .eq("activo", True)
        .is_("deleted_at", "null")
        .execute()
    )

    return [
        item["asignacion_id"]
        for item in (response.data or [])
    ]


def _validar_acceso_monitor_asignacion(
    supabase,
    *,
    asignacion_id: UUID,
    usuario_id: UUID,
) -> None:
    """
    Valida acceso de Monitor a asignación.
    """

    response = (
        supabase.table("asignacion_participantes")
        .select("id")
        .eq("asignacion_id", str(asignacion_id))
        .eq("usuario_id", str(usuario_id))
        .eq("activo", True)
        .is_("deleted_at", "null")
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No posee acceso a esta asignación.",
        )


# ============================================================
# HELPERS PATCH ASIGNACIÓN
# ============================================================


def _construir_estado_asignacion_resultante(
    *,
    asignacion_actual: AsignacionDetail,
    payload: AsignacionUpdate,
) -> dict:
    """
    Combina valores actuales con los campos enviados en PATCH.

    Un campo omitido conserva el valor actual.
    Un campo enviado explícitamente como None intenta limpiar el valor.
    """

    actual = asignacion_actual.model_dump()

    resultado = {
        "tipo_actividad_id": actual["tipo_actividad_id"],
        "colegio_id": actual["colegio_id"],
        "curso_colegio_id": actual["curso_colegio_id"],
        "sala_id": actual["sala_id"],
        "ramo_id": actual["ramo_id"],
        "espacio_reflexion_id": actual["espacio_reflexion_id"],
        "espacio_encuentro_id": actual["espacio_encuentro_id"],
        "fecha": actual["fecha"],
        "hora_inicio": actual["hora_inicio"],
        "hora_fin": actual["hora_fin"],
        "lugar": actual["lugar"],
        "observacion": actual["observacion"],
        "participantes": [
            {
                "usuario_id": participante.usuario_id,
                "tipo_participacion_id": (
                    participante.tipo_participacion_id
                ),
            }
            for participante in asignacion_actual.participantes
        ],
        "contactos": [
            {
                "contacto_colegio_id": (
                    contacto.contacto_colegio_id
                )
            }
            for contacto in asignacion_actual.contactos
        ],
    }

    for campo in payload.model_fields_set:
        valor = getattr(payload, campo)

        if campo == "contactos":
            resultado["contactos"] = [
                {
                    "contacto_colegio_id": (
                        contacto.contacto_colegio_id
                    )
                }
                for contacto in (valor or [])
            ]
        else:
            resultado[campo] = valor

    return resultado


def _validar_estado_asignacion_resultante(
    supabase,
    *,
    estado_resultante: dict,
) -> AsignacionCreate:
    """
    Reutiliza el schema y reglas de creación para validar el estado final.
    """

    try:
        payload_validado = AsignacionCreate.model_validate(
            estado_resultante
        )
    except ValidationError as exc:
        primer_error = exc.errors()[0]
        mensaje = primer_error.get(
            "msg",
            "Datos inválidos para la asignación.",
        )

        if mensaje.startswith("Value error, "):
            mensaje = mensaje.replace(
                "Value error, ",
                "",
                1,
            )

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=mensaje,
        )

    tipo = _obtener_tipo_actividad(
        supabase,
        tipo_actividad_id=payload_validado.tipo_actividad_id,
    )

    _validar_campos_tipo_actividad(
        supabase,
        payload=payload_validado,
        tipo_codigo=tipo["codigo"],
    )

    _validar_contactos(
        supabase,
        payload=payload_validado,
        tipo_codigo=tipo["codigo"],
    )

    return payload_validado


def _validar_reglas_edicion_asignacion(
    supabase,
    *,
    asignacion_actual: AsignacionDetail,
    payload: AsignacionUpdate,
) -> None:
    """
    Valida reglas generales previas al PATCH.
    """

    estado_codigo = _obtener_codigo_estado_asignacion(
        supabase,
        estado_id=asignacion_actual.estado_id,
    )

    if estado_codigo in {
        "CANCELADA",
        "NO_REALIZADA",
    }:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Una asignación {estado_codigo} no puede modificarse "
                "mediante el flujo normal."
            ),
        )

    if not payload.model_fields_set:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Debe enviar al menos un campo para actualizar.",
        )

    if "colegio_id" in payload.model_fields_set:
        nuevo_colegio = payload.colegio_id

        if nuevo_colegio != asignacion_actual.colegio_id:
            campos_requeridos = {
                "curso_colegio_id",
                "sala_id",
                "contactos",
            }

            faltantes = campos_requeridos.difference(
                payload.model_fields_set
            )

            if faltantes:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "Al cambiar el colegio debe volver a informar "
                        "curso_colegio_id, sala_id y contactos. Faltan: "
                        + ", ".join(sorted(faltantes))
                        + "."
                    ),
                )








# ============================================================
# GESTIÓN DE PARTICIPANTES - HELPERS
# ============================================================
















# ============================================================
# CICLO DE VIDA - HELPERS
# ============================================================








# ============================================================
# CANCELACIÓN / REAPERTURA - HELPERS
# ============================================================


# ============================================================
# ASISTENCIAS - HELPERS
# ============================================================




def _obtener_asistencia_por_participante(
    supabase,
    *,
    participante_id: UUID,
) -> dict:
    """
    Obtiene registro de asistencia desde PostgreSQL.
    """

    response = (
        supabase.table("asistencias_asignacion")
        .select(ASISTENCIA_SELECT)
        .eq(
            "asignacion_participante_id",
            str(participante_id),
        )
        .limit(1)
        .execute()
    )

    if not response.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "No existe registro de asistencia "
                "para esta participación."
            ),
        )

    return response.data[0]


def _obtener_asistencia_actualizada(
    supabase,
    *,
    participante_id: UUID,
) -> AsistenciaSummary:
    """
    Recupera asistencia y adapta nombres físicos
    al contrato de la API.
    """

    asistencia_db = _obtener_asistencia_por_participante(
        supabase,
        participante_id=participante_id,
    )

    return AsistenciaSummary.model_validate(
        _normalizar_asistencia_db(
            asistencia_db
        )
    )


# ============================================================
# GET - LISTAR
# ============================================================


@router.get(
    "",
    response_model=list[AsignacionListItem],
)
async def listar_asignaciones(
    tipo_actividad_id: UUID | None = None,
    colegio_id: UUID | None = None,
    estado_id: UUID | None = None,
    fecha_desde: date | None = None,
    fecha_hasta: date | None = None,
    activo: bool | None = None,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_ASSIGNMENTS")
    ),
) -> list[AsignacionListItem]:
    """
    Lista asignaciones visibles para el usuario.
    """

    supabase = get_supabase_client()

    try:
        query = (
            supabase.table("asignaciones")
            .select(ASIGNACION_SELECT)
            .is_("deleted_at", "null")
        )

        if current_user.role_code == "MONITOR":
            ids = _obtener_asignaciones_monitor(
                supabase,
                usuario_id=current_user.id,
            )

            if not ids:
                return []

            query = query.in_("id", ids)

        if tipo_actividad_id is not None:
            query = query.eq(
                "tipo_actividad_id",
                str(tipo_actividad_id),
            )

        if colegio_id is not None:
            query = query.eq(
                "colegio_id",
                str(colegio_id),
            )

        if estado_id is not None:
            query = query.eq(
                "estado_id",
                str(estado_id),
            )

        if fecha_desde is not None:
            query = query.gte(
                "fecha",
                fecha_desde.isoformat(),
            )

        if fecha_hasta is not None:
            query = query.lte(
                "fecha",
                fecha_hasta.isoformat(),
            )

        if activo is not None:
            query = query.eq(
                "activo",
                activo,
            )

        response = (
            query
            .order("fecha", desc=False)
            .order("hora_inicio", desc=False)
            .execute()
        )

        return [
            AsignacionListItem.model_validate(item)
            for item in (response.data or [])
        ]

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener las asignaciones.",
        )


# ============================================================
# GET - DETALLE
# ============================================================


@router.get(
    "/{asignacion_id}",
    response_model=AsignacionDetail,
)
async def obtener_asignacion(
    asignacion_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("VIEW_ASSIGNMENTS")
    ),
) -> AsignacionDetail:
    """
    Obtiene detalle de una asignación.
    """

    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("asignaciones")
            .select("id")
            .eq("id", str(asignacion_id))
            .is_("deleted_at", "null")
            .limit(1)
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="La asignación no existe.",
            )

        if current_user.role_code == "MONITOR":
            _validar_acceso_monitor_asignacion(
                supabase,
                asignacion_id=asignacion_id,
                usuario_id=current_user.id,
            )

        return _obtener_detalle_asignacion(
            supabase,
            asignacion_id=asignacion_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener la asignación.",
        )


# ============================================================
# PATCH - ACTUALIZAR ASIGNACIÓN
# ============================================================


@router.patch(
    "/{asignacion_id}",
    response_model=AsignacionDetail,
)
async def actualizar_asignacion(
    request: Request,
    asignacion_id: UUID,
    payload: AsignacionUpdate,
    current_user: AuthenticatedUser = Depends(
        require_permission("UPDATE_ASSIGNMENT")
    ),
) -> AsignacionDetail:
    """
    Actualiza una asignación de forma atómica.

    El backend conserva las validaciones funcionales existentes y PostgreSQL
    ejecuta dentro de una única transacción:
    - actualización parcial de la asignación;
    - reemplazo completo de contactos cuando fueron enviados;
    - auditoría UPDATE_ASSIGNMENT.

    La RPC usa updated_at como control optimista de concurrencia para evitar
    sobrescribir silenciosamente cambios realizados después de la lectura.
    """

    supabase = get_supabase_client()

    try:
        asignacion_actual = _obtener_detalle_asignacion(
            supabase,
            asignacion_id=asignacion_id,
        )

        _validar_reglas_edicion_asignacion(
            supabase,
            asignacion_actual=asignacion_actual,
            payload=payload,
        )

        estado_resultante = _construir_estado_asignacion_resultante(
            asignacion_actual=asignacion_actual,
            payload=payload,
        )

        payload_validado = _validar_estado_asignacion_resultante(
            supabase,
            estado_resultante=estado_resultante,
        )

        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        # Solo se envían a PostgreSQL los campos realmente incluidos
        # en el PATCH. Un valor None se mantiene como JSON null para
        # distinguir "limpiar el campo" de "campo omitido".
        cambios: dict = {}

        campos_uuid = {
            "colegio_id",
            "curso_colegio_id",
            "sala_id",
            "ramo_id",
            "espacio_reflexion_id",
            "espacio_encuentro_id",
        }

        for campo in payload.model_fields_set:
            if campo == "contactos":
                continue

            valor = getattr(payload, campo)

            if campo in campos_uuid:
                cambios[campo] = (
                    str(valor)
                    if valor is not None
                    else None
                )
            elif campo == "fecha":
                cambios[campo] = (
                    valor.isoformat()
                    if valor is not None
                    else None
                )
            elif campo in {"hora_inicio", "hora_fin"}:
                cambios[campo] = (
                    valor.isoformat()
                    if valor is not None
                    else None
                )
            else:
                cambios[campo] = valor

        reemplazar_contactos = (
            "contactos" in payload.model_fields_set
        )

        contactos = (
            [
                {
                    "contacto_colegio_id": str(
                        contacto.contacto_colegio_id
                    ),
                }
                for contacto in payload_validado.contactos
            ]
            if reemplazar_contactos
            else []
        )

        campos_modificados = sorted(
            payload.model_fields_set
        )

        response = supabase.rpc(
            "actualizar_asignacion_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_cambios": cambios,
                "p_reemplazar_contactos": reemplazar_contactos,
                "p_contactos": contactos,
                "p_expected_updated_at": (
                    asignacion_actual.updated_at.isoformat()
                ),
                "p_campos_modificados": campos_modificados,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de actualización devolvió "
                "una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asignación no puede modificarse "
                        "mediante el flujo normal."
                    ),
                )

            if error_code == "ASSIGNMENT_CHANGED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asignación cambió antes de completar "
                        "la actualización. Vuelva a cargarla."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para actualizar asignaciones."
                    ),
                )

            raise RuntimeError(
                "La RPC no pudo actualizar la asignación."
            )

        return _obtener_detalle_asignacion(
            supabase,
            asignacion_id=asignacion_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible actualizar la asignación.",
        )



# ============================================================
# POST - CANCELAR ASIGNACIÓN
# ============================================================


@router.post(
    "/{asignacion_id}/cancelar",
    response_model=AsignacionDetail,
)
async def cancelar_asignacion(
    request: Request,
    asignacion_id: UUID,
    payload: AsignacionCancelacionRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("CANCEL_ASSIGNMENT")
    ),
) -> AsignacionDetail:
    """
    Cancela una asignación PENDIENTE o CONFIRMADA de forma atómica.

    REGLAS:
    - SUPERADMIN, DIRECTIVA y COORDINADOR pueden cancelar porque poseen
      CANCEL_ASSIGNMENT;
    - el motivo es obligatorio;
    - REALIZADA, NO_REALIZADA y CANCELADA no pueden cancelarse;
    - participantes, contactos y asistencias se conservan;
    - estado, historial y auditoría se escriben dentro de una única
      transacción PostgreSQL mediante RPC.

    La RPC también vuelve a validar el estado dentro de un bloqueo de fila
    para evitar cancelaciones concurrentes o registros parciales.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "cancelar_asignacion_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_actor_user_id": str(current_user.id),
                "p_motivo": payload.motivo,
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de cancelación devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "INVALID_STATE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Solo se pueden cancelar asignaciones "
                        "PENDIENTES o CONFIRMADAS."
                    ),
                )

            if error_code == "ACTOR_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No fue posible validar al usuario que "
                        "ejecuta la cancelación."
                    ),
                )

            raise RuntimeError(
                "La RPC de cancelación no pudo completar la operación."
            )

        return _obtener_detalle_asignacion(
            supabase,
            asignacion_id=asignacion_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible cancelar la asignación.",
        )


# ============================================================
# POST - REABRIR ASIGNACIÓN
# ============================================================


@router.post(
    "/{asignacion_id}/reabrir",
    response_model=AsignacionDetail,
)
async def reabrir_asignacion(
    request: Request,
    asignacion_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("CANCEL_ASSIGNMENT")
    ),
) -> AsignacionDetail:
    """
    Reabre una asignación CANCELADA de forma atómica.

    REGLAS:
    - solo SUPERADMIN y DIRECTIVA pueden ejecutar esta operación;
    - la asignación debe estar CANCELADA;
    - se restaura exactamente el estado anterior registrado en la
      cancelación más reciente: PENDIENTE o CONFIRMADA;
    - estado, historial y auditoría se escriben dentro de una única
      transacción PostgreSQL mediante RPC.

    La RPC repite la validación del rol y bloquea la fila de asignación
    para impedir reaperturas concurrentes o estados parciales.
    """

    supabase = get_supabase_client()

    try:
        if current_user.role_code not in {
            "SUPERADMIN",
            "DIRECTIVA",
        }:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "Solo SUPERADMIN o DIRECTIVA pueden "
                    "reabrir una asignación cancelada."
                ),
            )

        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "reabrir_asignacion_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de reapertura devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "INVALID_STATE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Solo se puede reabrir una asignación "
                        "en estado CANCELADA."
                    ),
                )

            if error_code == "CANCELLATION_HISTORY_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No existe historial de cancelación suficiente "
                        "para reabrir la asignación."
                    ),
                )

            if error_code in {
                "INVALID_CANCELLATION_HISTORY",
                "INVALID_RESTORE_STATE",
            }:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El historial de cancelación contiene un estado "
                        "que no puede restaurarse."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN_ROLE",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Solo SUPERADMIN o DIRECTIVA pueden "
                        "reabrir una asignación cancelada."
                    ),
                )

            raise RuntimeError(
                "La RPC de reapertura no pudo completar la operación."
            )

        return _obtener_detalle_asignacion(
            supabase,
            asignacion_id=asignacion_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible reabrir la asignación.",
        )


# ============================================================
# POST - AGREGAR PARTICIPANTE
# ============================================================


@router.post(
    "/{asignacion_id}/participantes",
    response_model=ParticipanteSummary,
    status_code=status.HTTP_201_CREATED,
)
async def agregar_participante(
    request: Request,
    asignacion_id: UUID,
    payload: ParticipanteCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("REASSIGN_ASSIGNMENT")
    ),
) -> ParticipanteSummary:
    """
    Agrega un participante a una asignación de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validación del actor y permiso REASSIGN_ASSIGNMENT;
    - validación de la asignación y su estado;
    - validación del usuario participante;
    - validación del tipo de participación;
    - control de participación activa duplicada;
    - creación de participación PENDIENTE;
    - creación automática de asistencia PENDIENTE mediante trigger;
    - auditoría ADD_PARTICIPANT.

    Si cualquier paso falla, PostgreSQL revierte toda la operación.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "agregar_participante_atomico",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_usuario_id": str(payload.usuario_id),
                "p_tipo_participacion_id": str(
                    payload.tipo_participacion_id
                ),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de agregar participante devolvió "
                "una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No se pueden modificar participantes de una "
                        "asignación cerrada."
                    ),
                )

            if error_code == "PARTICIPANT_USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El usuario seleccionado no existe.",
                )

            if error_code == "PARTICIPANT_USER_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El usuario seleccionado no está disponible."
                    ),
                )

            if error_code == "INVALID_PARTICIPANT_ROLE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El usuario seleccionado no puede ser participante."
                    ),
                )

            if error_code == "PARTICIPATION_TYPE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El tipo de participación no existe o está inactivo."
                    ),
                )

            if error_code == "ACTIVE_PARTICIPATION_EXISTS":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El usuario ya posee una participación activa "
                        "en esta asignación."
                    ),
                )

            if error_code == "PENDING_STATE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        "No existe un estado PENDIENTE activo para "
                        "participaciones."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para agregar participantes."
                    ),
                )

            raise RuntimeError(
                "La RPC de agregar participante no pudo completar "
                "la operación."
            )

        participante_id = resultado.get("participante_id")

        if not participante_id:
            raise RuntimeError(
                "La RPC no devolvió el participante creado."
            )

        response_participante = (
            supabase.table("asignacion_participantes")
            .select(PARTICIPANTE_SELECT)
            .eq("id", participante_id)
            .limit(1)
            .execute()
        )

        if not response_participante.data:
            raise RuntimeError(
                "No fue posible recuperar el participante creado."
            )

        return ParticipanteSummary.model_validate(
            response_participante.data[0]
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible agregar el participante.",
        )



# ============================================================
# DELETE - ARCHIVAR PARTICIPANTE
# ============================================================


@router.delete(
    "/{asignacion_id}/participantes/{participante_id}",
    response_model=ParticipanteSummary,
)
async def quitar_participante(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("REASSIGN_ASSIGNMENT")
    ),
) -> ParticipanteSummary:
    """
    Archiva un participante de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validaciones críticas de actor, asignación y participación;
    - soft-delete de la participación;
    - conservación de asistencia e historial;
    - eventual transición CONFIRMADA -> PENDIENTE si se retiró el último
      RELATOR ACEPTADO activo;
    - auditoría de la eliminación lógica y del cambio de estado, si aplica.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "quitar_participante_atomico",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de eliminación de participante devolvió "
                "una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No se pueden modificar participantes de una "
                        "asignación REALIZADA, CANCELADA o NO_REALIZADA."
                    ),
                )

            if error_code == "PARTICIPANT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe, no pertenece a esta "
                        "asignación o ya fue archivada."
                    ),
                )

            if error_code == "PARTICIPANT_CHANGED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La participación cambió antes de completar "
                        "la operación."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No posee permiso para quitar participantes.",
                )

            raise RuntimeError(
                "La RPC de eliminación de participante no pudo "
                "completar la operación."
            )

        participante_response = (
            supabase.table("asignacion_participantes")
            .select(PARTICIPANTE_SELECT)
            .eq("id", str(participante_id))
            .limit(1)
            .execute()
        )

        if not participante_response.data:
            raise RuntimeError(
                "No fue posible recuperar la participación archivada."
            )

        return ParticipanteSummary.model_validate(
            participante_response.data[0]
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible quitar el participante.",
        )


# ============================================================
# PATCH - CAMBIAR TIPO PARTICIPACIÓN
# ============================================================


@router.patch(
    "/{asignacion_id}/participantes/{participante_id}/tipo",
    response_model=ParticipanteSummary,
)
async def cambiar_tipo_participacion(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    payload: ParticipanteTipoUpdateRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("REASSIGN_ASSIGNMENT")
    ),
) -> ParticipanteSummary:
    """
    Cambia el tipo de participación de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validaciones críticas de actor, asignación, usuario y tipo;
    - actualización directa si la participación sigue PENDIENTE;
    - archivado y creación de una nueva PENDIENTE si ya fue respondida;
    - creación automática de asistencia para la nueva participación;
    - eventual transición CONFIRMADA -> PENDIENTE;
    - auditoría de todos los cambios asociados.

    Las participaciones ACEPTADAS o RECHAZADAS se conservan como historial.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "cambiar_tipo_participacion_atomico",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_nuevo_tipo_participacion_id": str(
                    payload.tipo_participacion_id
                ),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de cambio de tipo devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No se pueden modificar participantes de una "
                        "asignación REALIZADA, CANCELADA o NO_REALIZADA."
                    ),
                )

            if error_code == "PARTICIPANT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe, no pertenece a esta "
                        "asignación o ya fue archivada."
                    ),
                )

            if error_code == "PARTICIPANT_USER_NOT_AVAILABLE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El usuario de la participación no está disponible "
                        "para participar en asignaciones."
                    ),
                )

            if error_code == "PARTICIPATION_TYPE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El tipo de participación no existe o está inactivo."
                    ),
                )

            if error_code == "SAME_PARTICIPATION_TYPE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La participación ya posee el tipo seleccionado."
                    ),
                )

            if error_code == "INVALID_PARTICIPATION_STATE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El estado actual de la participación no permite "
                        "cambiar su tipo."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para cambiar el tipo de "
                        "participación."
                    ),
                )

            raise RuntimeError(
                "La RPC de cambio de tipo no pudo completar la operación."
            )

        participante_resultado_id = resultado.get(
            "participante_resultado_id"
        )

        if not participante_resultado_id:
            raise RuntimeError(
                "La RPC no informó la participación resultante."
            )

        participante_response = (
            supabase.table("asignacion_participantes")
            .select(PARTICIPANTE_SELECT)
            .eq("id", str(participante_resultado_id))
            .limit(1)
            .execute()
        )

        if not participante_response.data:
            raise RuntimeError(
                "No fue posible recuperar la participación resultante."
            )

        return ParticipanteSummary.model_validate(
            participante_response.data[0]
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "No fue posible cambiar el tipo de participación."
            ),
        )


# ============================================================
# POST - REASIGNAR PARTICIPANTE
# ============================================================


@router.post(
    "/{asignacion_id}/participantes/{participante_id}/reasignar",
    response_model=ParticipanteSummary,
    status_code=status.HTTP_201_CREATED,
)
async def reasignar_participante(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    payload: ParticipanteReasignacionRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("REASSIGN_ASSIGNMENT")
    ),
) -> ParticipanteSummary:
    """
    Reasigna una participación a otro usuario de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validaciones críticas de concurrencia y negocio;
    - archivado de la participación anterior;
    - creación de la nueva participación PENDIENTE;
    - creación automática de su asistencia mediante el trigger existente;
    - eventual transición CONFIRMADA -> PENDIENTE;
    - auditoría de la reasignación y del cambio de estado, si corresponde.

    La participación anterior y su asistencia permanecen como historial.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "reasignar_participante_atomico",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_nuevo_usuario_id": str(payload.nuevo_usuario_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de reasignación devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No se pueden modificar participantes de una "
                        "asignación REALIZADA, CANCELADA o NO_REALIZADA."
                    ),
                )

            if error_code == "PARTICIPANT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe o no pertenece "
                        "a esta asignación."
                    ),
                )

            if error_code == "SAME_USER":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El nuevo usuario es el mismo participante actual."
                    ),
                )

            if error_code == "NEW_USER_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "El nuevo usuario no existe o se encuentra inactivo."
                    ),
                )

            if error_code == "NEW_USER_CANNOT_PARTICIPATE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El rol del nuevo usuario no puede participar "
                        "en asignaciones."
                    ),
                )

            if error_code == "NEW_USER_ALREADY_PARTICIPATES":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El usuario ya posee una participación activa "
                        "en esta asignación."
                    ),
                )

            if error_code == "PARTICIPATION_TYPE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El tipo de participación no existe o está inactivo."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para reasignar participantes."
                    ),
                )

            raise RuntimeError(
                "La RPC de reasignación no pudo completar la operación."
            )

        nueva_participacion_id = resultado.get(
            "nuevo_participante_id"
        )

        if not nueva_participacion_id:
            raise RuntimeError(
                "La RPC no informó la nueva participación creada."
            )

        nueva_response = (
            supabase.table("asignacion_participantes")
            .select(PARTICIPANTE_SELECT)
            .eq("id", str(nueva_participacion_id))
            .limit(1)
            .execute()
        )

        if not nueva_response.data:
            raise RuntimeError(
                "No fue posible recuperar la nueva participación."
            )

        return ParticipanteSummary.model_validate(
            nueva_response.data[0]
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible reasignar el participante.",
        )


# ============================================================
# POST - CREAR ASIGNACIÓN
# ============================================================


@router.post(
    "",
    response_model=AsignacionDetail,
    status_code=status.HTTP_201_CREATED,
)
async def crear_asignacion(
    request: Request,
    payload: AsignacionCreate,
    current_user: AuthenticatedUser = Depends(
        require_permission("CREATE_ASSIGNMENT")
    ),
) -> AsignacionDetail:
    """
    Crea una asignación completa de forma atómica.

    Las validaciones funcionales del payload se mantienen en el backend
    para conservar el contrato actual. PostgreSQL ejecuta en una sola
    transacción la creación de:
    - asignación;
    - participantes PENDIENTES;
    - asistencias PENDIENTES generadas por trigger;
    - contactos;
    - auditoría CREATE_ASSIGNMENT.

    Si cualquiera de esas escrituras falla, no queda información parcial.
    """

    supabase = get_supabase_client()

    try:
        tipo = _obtener_tipo_actividad(
            supabase,
            tipo_actividad_id=payload.tipo_actividad_id,
        )

        tipo_codigo = tipo["codigo"]

        # Las reglas de negocio ya existentes se validan antes de abrir
        # la transacción de escritura. La RPC vuelve a validar actor y
        # permiso para no confiar solo en la capa HTTP.
        _validar_permiso_tipo_actividad(
            supabase,
            role_code=current_user.role_code,
            tipo_codigo=tipo_codigo,
        )

        _validar_campos_tipo_actividad(
            supabase,
            payload=payload,
            tipo_codigo=tipo_codigo,
        )

        _validar_participantes(
            supabase,
            payload=payload,
        )

        _validar_contactos(
            supabase,
            payload=payload,
            tipo_codigo=tipo_codigo,
        )

        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        participantes = [
            {
                "usuario_id": str(participante.usuario_id),
                "tipo_participacion_id": str(
                    participante.tipo_participacion_id
                ),
            }
            for participante in payload.participantes
        ]

        contactos = [
            {
                "contacto_colegio_id": str(
                    contacto.contacto_colegio_id
                ),
            }
            for contacto in payload.contactos
        ]

        response = supabase.rpc(
            "crear_asignacion_atomica",
            {
                "p_tipo_actividad_id": str(
                    payload.tipo_actividad_id
                ),
                "p_colegio_id": (
                    str(payload.colegio_id)
                    if payload.colegio_id
                    else None
                ),
                "p_curso_colegio_id": (
                    str(payload.curso_colegio_id)
                    if payload.curso_colegio_id
                    else None
                ),
                "p_sala_id": (
                    str(payload.sala_id)
                    if payload.sala_id
                    else None
                ),
                "p_ramo_id": (
                    str(payload.ramo_id)
                    if payload.ramo_id
                    else None
                ),
                "p_espacio_reflexion_id": (
                    str(payload.espacio_reflexion_id)
                    if payload.espacio_reflexion_id
                    else None
                ),
                "p_espacio_encuentro_id": (
                    str(payload.espacio_encuentro_id)
                    if payload.espacio_encuentro_id
                    else None
                ),
                "p_fecha": payload.fecha.isoformat(),
                "p_hora_inicio": payload.hora_inicio.isoformat(),
                "p_hora_fin": payload.hora_fin.isoformat(),
                "p_lugar": payload.lugar,
                "p_observacion": payload.observacion,
                "p_participantes": participantes,
                "p_contactos": contactos,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de creación de asignación devolvió "
                "una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para crear asignaciones."
                    ),
                )

            if error_code == "PENDING_ASSIGNMENT_STATE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        "No existe un estado PENDIENTE activo "
                        "para asignaciones."
                    ),
                )

            if error_code == "PENDING_PARTICIPATION_STATE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        "No existe un estado PENDIENTE activo "
                        "para participaciones."
                    ),
                )

            if error_code == "INVALID_PARTICIPANTS":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "La asignación debe incluir al menos "
                        "un participante válido."
                    ),
                )

            raise RuntimeError(
                "La RPC no pudo crear la asignación."
            )

        asignacion_id = resultado.get("asignacion_id")

        if not asignacion_id:
            raise RuntimeError(
                "La RPC no devolvió la asignación creada."
            )

        return _obtener_detalle_asignacion(
            supabase,
            asignacion_id=UUID(asignacion_id),
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible crear la asignación.",
        )



# ============================================================
# POST - ACEPTAR
# ============================================================


@router.post(
    "/{asignacion_id}/participaciones/{participante_id}/aceptar",
    response_model=ParticipanteSummary,
)
async def aceptar_participacion(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    current_user: AuthenticatedUser = Depends(
        require_permission("ACCEPT_PARTICIPATION")
    ),
) -> ParticipanteSummary:
    """
    Acepta una participación PENDIENTE de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validación del actor y del permiso ACCEPT_PARTICIPATION;
    - validación de la asignación y de la participación;
    - verificación de que responde el propio participante;
    - transición de la participación PENDIENTE -> ACEPTADA;
    - auditoría de la aceptación;
    - eventual transición de la asignación PENDIENTE -> CONFIRMADA
      cuando quien acepta es un RELATOR;
    - auditoría de la confirmación automática, si corresponde.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "aceptar_participacion_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de aceptación devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asignación ya no admite respuestas "
                        "de participantes."
                    ),
                )

            if error_code == "PARTICIPANT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe o no pertenece "
                        "a esta asignación."
                    ),
                )

            if error_code == "NOT_PARTICIPANT_OWNER":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Solo el participante asignado puede "
                        "responder esta participación."
                    ),
                )

            if error_code == "PARTICIPATION_ALREADY_RESPONDED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La participación ya fue respondida "
                        "anteriormente."
                    ),
                )

            if error_code == "PARTICIPATION_CHANGED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La participación cambió de estado "
                        "antes de completar la operación."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para aceptar participaciones."
                    ),
                )

            raise RuntimeError(
                "La RPC de aceptación no pudo completar la operación."
            )

        return _obtener_participacion_actualizada(
            supabase,
            participante_id=participante_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible aceptar la participación.",
        )


# ============================================================
# POST - RECHAZAR
# ============================================================


@router.post(
    "/{asignacion_id}/participaciones/{participante_id}/rechazar",
    response_model=ParticipanteSummary,
)
async def rechazar_participacion(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    payload: ParticipacionRechazoRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("REJECT_PARTICIPATION")
    ),
) -> ParticipanteSummary:
    """
    Rechaza una participación PENDIENTE de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validación del actor y permiso REJECT_PARTICIPATION;
    - validación de asignación operativa;
    - validación de participación activa y PENDIENTE;
    - comprobación de que responde el propio participante;
    - actualización a RECHAZADA con motivo obligatorio;
    - auditoría REJECT_PARTICIPATION.

    La asistencia PENDIENTE asociada se conserva como historial.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "rechazar_participacion_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_motivo": payload.motivo,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de rechazo devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asignación ya no admite respuestas "
                        "de participantes."
                    ),
                )

            if error_code == "PARTICIPATION_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe o no pertenece "
                        "a esta asignación."
                    ),
                )

            if error_code == "NOT_PARTICIPANT_OWNER":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Solo el participante asignado puede "
                        "responder esta participación."
                    ),
                )

            if error_code == "PARTICIPATION_ALREADY_RESPONDED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La participación ya fue respondida "
                        "anteriormente."
                    ),
                )

            if error_code == "INVALID_REJECTION_REASON":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El motivo del rechazo es obligatorio."
                    ),
                )

            if error_code == "REJECTED_STATE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        "No existe un estado RECHAZADA activo "
                        "para participaciones."
                    ),
                )

            if error_code == "PARTICIPATION_CHANGED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La participación cambió de estado "
                        "antes de completar la operación."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para rechazar participaciones."
                    ),
                )

            raise RuntimeError(
                "La RPC de rechazo no pudo completar la operación."
            )

        return _obtener_participacion_actualizada(
            supabase,
            participante_id=participante_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible rechazar la participación.",
        )



# ============================================================
# POST - REABRIR PARTICIPACIÓN RECHAZADA
# ============================================================


@router.post(
    "/{asignacion_id}/participaciones/{participante_id}/reabrir",
    response_model=ParticipanteSummary,
    status_code=status.HTTP_201_CREATED,
)
async def reabrir_participacion(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    payload: ParticipacionReaperturaRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("REASSIGN_ASSIGNMENT")
    ),
) -> ParticipanteSummary:
    """
    Reabre de forma atómica una participación RECHAZADA.

    PostgreSQL ejecuta en una sola transacción:
    - validaciones críticas de actor, asignación y participación;
    - archivado de la participación rechazada;
    - creación de una nueva participación PENDIENTE para el mismo usuario;
    - creación automática de su asistencia mediante el trigger existente;
    - auditoría de la reapertura con el motivo informado.

    La participación rechazada y su asistencia permanecen como historial.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "reabrir_participacion_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_motivo": payload.motivo,
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de reapertura devolvió una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No se pueden modificar participantes de una "
                        "asignación REALIZADA, CANCELADA o NO_REALIZADA."
                    ),
                )

            if error_code == "PARTICIPANT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe o no pertenece "
                        "a esta asignación."
                    ),
                )

            if error_code == "PARTICIPATION_NOT_REJECTED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Solo se puede reabrir una participación "
                        "en estado RECHAZADA."
                    ),
                )

            if error_code == "PARTICIPANT_USER_NOT_AVAILABLE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El usuario de la participación no está disponible "
                        "para participar en asignaciones."
                    ),
                )

            if error_code == "PARTICIPATION_TYPE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El tipo de participación no existe o está inactivo."
                    ),
                )

            if error_code == "USER_ALREADY_PARTICIPATES":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El usuario ya posee otra participación activa "
                        "en esta asignación."
                    ),
                )

            if error_code == "INVALID_REASON":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El motivo de reapertura debe contener entre "
                        "3 y 1000 caracteres."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN_ROLE",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Solo SUPERADMIN, DIRECTIVA o COORDINADOR pueden "
                        "reabrir una participación rechazada."
                    ),
                )

            raise RuntimeError(
                "La RPC de reapertura no pudo completar la operación."
            )

        nueva_participacion_id = resultado.get(
            "nuevo_participante_id"
        )

        if not nueva_participacion_id:
            raise RuntimeError(
                "La RPC no informó la nueva participación creada."
            )

        nueva_response = (
            supabase.table("asignacion_participantes")
            .select(PARTICIPANTE_SELECT)
            .eq("id", str(nueva_participacion_id))
            .limit(1)
            .execute()
        )

        if not nueva_response.data:
            raise RuntimeError(
                "No fue posible recuperar la nueva participación."
            )

        return ParticipanteSummary.model_validate(
            nueva_response.data[0]
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible reabrir la participación.",
        )


# ============================================================
# POST - ASISTENCIA PROPIA
# ============================================================


@router.post(
    "/{asignacion_id}/participaciones/{participante_id}/asistencia",
    response_model=AsistenciaSummary,
)
async def registrar_asistencia_propia(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    payload: AsistenciaPropiaRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("REPORT_ATTENDANCE")
    ),
) -> AsistenciaSummary:
    """
    Registra la asistencia propia de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validación del actor y permiso REPORT_ATTENDANCE;
    - evaluación previa del ciclo de vida;
    - validación de asignación y ventana temporal;
    - validación de participación ACEPTADA y propiedad;
    - validación de asistencia PENDIENTE;
    - registro de estado, motivo y geolocalización;
    - auditoría REPORT_ATTENDANCE;
    - evaluación posterior del ciclo de vida.

    Si la actividad ya terminó y existe una asistencia PRESENTE,
    la asignación puede pasar a REALIZADA dentro de la misma transacción.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "registrar_asistencia_propia_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_estado": payload.estado,
                "p_motivo": payload.motivo,
                "p_latitud": payload.latitud,
                "p_longitud": payload.longitud,
                "p_precision_metros": payload.precision_gps,
                "p_fecha_geolocalizacion": (
                    payload.fecha_geolocalizacion.isoformat()
                ),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de asistencia propia devolvió "
                "una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CLOSED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asignación ya no admite marcación "
                        "de asistencia propia."
                    ),
                )

            if error_code == "ATTENDANCE_NOT_STARTED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asistencia propia solo puede registrarse "
                        "desde la hora de inicio de la asignación."
                    ),
                )

            if error_code == "ATTENDANCE_WINDOW_EXPIRED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "El plazo para registrar asistencia propia venció. "
                        "Después de 24 horas desde el término solo puede "
                        "regularizarse administrativamente."
                    ),
                )

            if error_code == "PARTICIPATION_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe o no pertenece "
                        "a esta asignación."
                    ),
                )

            if error_code == "NOT_PARTICIPANT_OWNER":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Solo el participante asignado puede "
                        "registrar su propia asistencia."
                    ),
                )

            if error_code == "PARTICIPATION_NOT_ACCEPTED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Solo una participación ACEPTADA puede "
                        "registrar asistencia."
                    ),
                )

            if error_code == "ATTENDANCE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "No existe registro de asistencia "
                        "para esta participación."
                    ),
                )

            if error_code == "ATTENDANCE_ALREADY_REPORTED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asistencia ya fue informada anteriormente."
                    ),
                )

            if error_code == "INVALID_ATTENDANCE_STATE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El estado debe ser PRESENTE, AUSENTE "
                        "o JUSTIFICADA."
                    ),
                )

            if error_code == "ATTENDANCE_REASON_REQUIRED":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "AUSENTE y JUSTIFICADA requieren motivo."
                    ),
                )

            if error_code == "INVALID_GEOLOCATION":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "La geolocalización informada no es válida."
                    ),
                )

            if error_code == "ATTENDANCE_CHANGED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asistencia cambió antes de completar "
                        "la operación."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para registrar asistencia."
                    ),
                )

            raise RuntimeError(
                "La RPC de asistencia propia no pudo completar "
                "la operación."
            )

        return _obtener_asistencia_actualizada(
            supabase,
            participante_id=participante_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible registrar la asistencia.",
        )



# ============================================================
# PATCH - REGULARIZAR ASISTENCIA
# ============================================================


@router.patch(
    "/{asignacion_id}/participaciones/{participante_id}/asistencia/regularizar",
    response_model=AsistenciaSummary,
)
async def regularizar_asistencia(
    request: Request,
    asignacion_id: UUID,
    participante_id: UUID,
    payload: AsistenciaRegularizacionRequest,
    current_user: AuthenticatedUser = Depends(
        require_permission("MANAGE_ATTENDANCE")
    ),
) -> AsistenciaSummary:
    """
    Regulariza administrativamente una asistencia de forma atómica.

    PostgreSQL ejecuta en una sola transacción:
    - validación del actor y permiso MANAGE_ATTENDANCE;
    - validación de la asignación;
    - validación de participación ACEPTADA;
    - actualización de la asistencia;
    - auditoría MANAGE_ATTENDANCE;
    - eventual transición NO_REALIZADA -> REALIZADA;
    - historial y auditoría del cambio global de estado.

    La regularización administrativa no modifica las coordenadas GPS
    históricas almacenadas en la asistencia.
    """

    supabase = get_supabase_client()

    try:
        request_id_raw = getattr(
            request.state,
            "request_id",
            None,
        )

        client_ip = (
            request.client.host
            if request.client
            else None
        )

        response = supabase.rpc(
            "regularizar_asistencia_atomica",
            {
                "p_asignacion_id": str(asignacion_id),
                "p_participante_id": str(participante_id),
                "p_estado": payload.estado,
                "p_motivo": payload.motivo,
                "p_motivo_regularizacion": (
                    payload.motivo_regularizacion
                ),
                "p_actor_user_id": str(current_user.id),
                "p_request_id": (
                    str(request_id_raw)
                    if request_id_raw is not None
                    else None
                ),
                "p_ip_address": client_ip,
                "p_user_agent": request.headers.get(
                    "user-agent"
                ),
            },
        ).execute()

        resultado = response.data

        if not isinstance(resultado, dict):
            raise RuntimeError(
                "La RPC de regularización devolvió "
                "una respuesta inválida."
            )

        if resultado.get("ok") is not True:
            error_code = resultado.get("error_code")

            if error_code == "ASSIGNMENT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La asignación no existe.",
                )

            if error_code == "ASSIGNMENT_INACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="La asignación se encuentra inactiva.",
                )

            if error_code == "ASSIGNMENT_CANCELLED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "No se puede regularizar asistencia de una "
                        "asignación CANCELADA."
                    ),
                )

            if error_code == "NO_REALIZADA_FORBIDDEN_ROLE":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Solo DIRECTIVA o SUPERADMIN pueden modificar "
                        "una asignación NO_REALIZADA."
                    ),
                )

            if error_code == "PARTICIPANT_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "La participación no existe o no pertenece "
                        "a esta asignación."
                    ),
                )

            if error_code == "PARTICIPATION_NOT_ACCEPTED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "Solo una participación ACEPTADA puede "
                        "regularizar asistencia."
                    ),
                )

            if error_code == "ATTENDANCE_NOT_FOUND":
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=(
                        "No existe registro de asistencia "
                        "para esta participación."
                    ),
                )

            if error_code == "INVALID_ATTENDANCE_STATE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El estado debe ser PRESENTE, AUSENTE "
                        "o JUSTIFICADA."
                    ),
                )

            if error_code == "ATTENDANCE_REASON_REQUIRED":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "AUSENTE y JUSTIFICADA requieren motivo."
                    ),
                )

            if error_code == "INVALID_REGULARIZATION_REASON":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        "El motivo de regularización debe contener "
                        "entre 3 y 1000 caracteres."
                    ),
                )

            if error_code == "ASSIGNMENT_STATE_CHANGED":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        "La asignación cambió de estado antes de "
                        "completar la regularización."
                    ),
                )

            if error_code in {
                "ACTOR_NOT_FOUND",
                "FORBIDDEN",
            }:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "No posee permiso para regularizar asistencias."
                    ),
                )

            raise RuntimeError(
                "La RPC de regularización no pudo completar "
                "la operación."
            )

        return _obtener_asistencia_actualizada(
            supabase,
            participante_id=participante_id,
        )

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible regularizar la asistencia.",
        )
