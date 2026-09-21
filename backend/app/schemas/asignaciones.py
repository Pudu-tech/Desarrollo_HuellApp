"""
Schemas Pydantic del módulo de asignaciones de HuellAPP.

Este módulo define:
- creación y actualización parcial de asignaciones;
- participantes;
- contactos asociados;
- listado y detalle de asignaciones;
- aceptación y rechazo de participaciones;
- cancelación y reapertura de asignaciones;
- registro y regularización de asistencias.

REGLAS IMPORTANTES:
- El usuario autenticado nunca se recibe desde el frontend.
- El estado inicial de una participación no se recibe desde frontend.
- El rechazo requiere obligatoriamente un motivo.
- La reapertura de una participación RECHAZADA requiere un motivo.
- La cancelación de una asignación requiere obligatoriamente un motivo.
- La aceptación no requiere información adicional.
- La asistencia propia exige geolocalización.
- La geolocalización propia incluye fecha/hora de captura.
- AUSENTE y JUSTIFICADA requieren motivo.
- La regularización administrativa exige motivo de regularización.
- Dirección, comuna y región detectadas NO son ingresadas manualmente
  por el usuario.
- Dirección, comuna y región serán obtenidas mediante reverse geocoding
  a partir de latitud y longitud.
"""

from datetime import date, datetime, time
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


# ============================================================
# HELPERS
# ============================================================


def _normalizar_texto_opcional(
    value: str | None,
) -> str | None:
    """
    Elimina espacios innecesarios de textos opcionales.

    Si el texto queda vacío después de aplicar strip(),
    se transforma en None.
    """

    if value is None:
        return None

    value = value.strip()

    return value or None


# ============================================================
# PARTICIPANTES - CREACIÓN
# ============================================================


class ParticipanteCreate(BaseModel):
    """
    Participante que será incorporado a una asignación.

    El estado de participación no se recibe desde frontend.
    Backend siempre crea la participación en estado PENDIENTE.
    """

    usuario_id: UUID
    tipo_participacion_id: UUID


class ParticipanteTipoUpdateRequest(BaseModel):
    """
    Payload para modificar el tipo de participación de un participante.

    Si la participación todavía está PENDIENTE, el backend puede actualizar
    el registro actual. Si ya fue ACEPTADA o RECHAZADA, el backend conserva
    ese registro como histórico y crea una nueva participación PENDIENTE.
    """

    model_config = ConfigDict(extra="forbid")

    tipo_participacion_id: UUID


class ParticipanteReasignacionRequest(BaseModel):
    """
    Payload para reasignar una participación a otro usuario.

    La reasignación no sobrescribe el usuario histórico: el backend archiva
    la participación anterior y crea una nueva participación PENDIENTE para
    el nuevo usuario, conservando el mismo tipo de participación.
    """

    model_config = ConfigDict(extra="forbid")

    nuevo_usuario_id: UUID


# ============================================================
# PARTICIPANTES - RESPUESTAS
# ============================================================


class ParticipacionRechazoRequest(BaseModel):
    """
    Datos requeridos para rechazar una participación.

    El usuario que responde se obtiene desde la sesión autenticada.
    """

    motivo: str = Field(
        ...,
        min_length=3,
        max_length=1000,
        description="Motivo obligatorio del rechazo.",
    )

    @field_validator("motivo")
    @classmethod
    def normalizar_motivo(
        cls,
        value: str,
    ) -> str:
        """
        Limpia el motivo y evita textos compuestos únicamente
        por espacios.
        """

        value = value.strip()

        if not value:
            raise ValueError(
                "El motivo del rechazo es obligatorio."
            )

        return value


class ParticipacionReaperturaRequest(BaseModel):
    """
    Datos requeridos para reabrir una participación RECHAZADA.

    La reapertura es una corrección administrativa y siempre debe dejar
    trazabilidad del motivo. El actor se obtiene desde la sesión autenticada.
    """

    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(
        ...,
        min_length=3,
        max_length=1000,
        description="Motivo obligatorio de la reapertura de participación.",
    )

    @field_validator("motivo")
    @classmethod
    def normalizar_motivo_reapertura(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza el motivo y evita valores compuestos solo por espacios.
        """

        value = value.strip()

        if not value:
            raise ValueError(
                "El motivo de la reapertura es obligatorio."
            )

        return value


# ============================================================
# ASIGNACIÓN - CANCELACIÓN
# ============================================================


class AsignacionCancelacionRequest(BaseModel):
    """
    Payload requerido para cancelar una asignación.

    La cancelación siempre exige un motivo explícito. El actor y el
    estado CANCELADA se determinan en backend y nunca se reciben desde
    el frontend.
    """

    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(
        ...,
        min_length=3,
        max_length=1000,
        description="Motivo obligatorio de la cancelación.",
    )

    @field_validator("motivo")
    @classmethod
    def normalizar_motivo_cancelacion(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza el motivo y evita valores compuestos solo por espacios.
        """

        value = value.strip()

        if not value:
            raise ValueError(
                "El motivo de la cancelación es obligatorio."
            )

        return value


# ============================================================
# PARTICIPANTES - RESPUESTA API
# ============================================================


class ParticipanteSummary(BaseModel):
    """
    Resumen de un participante asociado a una asignación.
    """

    id: UUID
    usuario_id: UUID
    tipo_participacion_id: UUID
    estado_participacion_id: UUID

    motivo_rechazo: str | None = None
    fecha_respuesta: datetime | None = None
    respondido_por: UUID | None = None

    activo: bool


# ============================================================
# ASISTENCIA - REGISTRO PROPIO
# ============================================================


class AsistenciaPropiaRequest(BaseModel):
    """
    Payload utilizado por un participante para registrar
    su propia asistencia.

    El frontend únicamente informa los datos técnicos capturados
    por el dispositivo.

    REGLAS:
    - estado permitido: PRESENTE, AUSENTE o JUSTIFICADA;
    - latitud y longitud son obligatorias;
    - fecha_geolocalizacion es obligatoria;
    - precisión GPS es opcional;
    - AUSENTE y JUSTIFICADA requieren motivo;
    - dirección, comuna y región NO son recibidas desde frontend.

    Los datos legibles de ubicación serán derivados posteriormente
    mediante reverse geocoding.
    """

    estado: str = Field(
        ...,
        description="PRESENTE, AUSENTE o JUSTIFICADA.",
    )

    motivo: str | None = Field(
        default=None,
        max_length=1000,
    )

    latitud: float = Field(
        ...,
        ge=-90,
        le=90,
    )

    longitud: float = Field(
        ...,
        ge=-180,
        le=180,
    )

    precision_gps: float | None = Field(
        default=None,
        ge=0,
        description=(
            "Precisión aproximada entregada por el dispositivo, "
            "expresada en metros."
        ),
    )

    fecha_geolocalizacion: datetime = Field(
        ...,
        description=(
            "Fecha y hora en que el dispositivo obtuvo "
            "las coordenadas."
        ),
    )

    @field_validator(
        "estado",
        mode="before",
    )
    @classmethod
    def normalizar_estado(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza el código de estado recibido.
        """

        return value.strip().upper()

    @field_validator(
        "motivo",
        mode="before",
    )
    @classmethod
    def normalizar_motivo_asistencia(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza el motivo opcional.
        """

        return _normalizar_texto_opcional(value)

    @model_validator(mode="after")
    def validar_reglas_asistencia(
        self,
    ) -> "AsistenciaPropiaRequest":
        """
        Valida estados permitidos y motivo obligatorio.
        """

        estados_permitidos = {
            "PRESENTE",
            "AUSENTE",
            "JUSTIFICADA",
        }

        if self.estado not in estados_permitidos:
            raise ValueError(
                "El estado debe ser PRESENTE, AUSENTE o JUSTIFICADA."
            )

        if (
            self.estado in {
                "AUSENTE",
                "JUSTIFICADA",
            }
            and not self.motivo
        ):
            raise ValueError(
                "AUSENTE y JUSTIFICADA requieren motivo."
            )

        if self.estado == "PRESENTE":
            self.motivo = None

        return self


# ============================================================
# ASISTENCIA - REGULARIZACIÓN ADMINISTRATIVA
# ============================================================


class AsistenciaRegularizacionRequest(BaseModel):
    """
    Payload utilizado para regularizar administrativamente
    una asistencia.

    La regularización:
    - no requiere GPS;
    - exige motivo_regularizacion;
    - puede establecer PRESENTE, AUSENTE o JUSTIFICADA;
    - AUSENTE y JUSTIFICADA requieren además un motivo.
    """

    estado: str = Field(
        ...,
        description="PRESENTE, AUSENTE o JUSTIFICADA.",
    )

    motivo: str | None = Field(
        default=None,
        max_length=1000,
    )

    motivo_regularizacion: str = Field(
        ...,
        min_length=3,
        max_length=1000,
    )

    @field_validator(
        "estado",
        mode="before",
    )
    @classmethod
    def normalizar_estado(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza el código de estado recibido.
        """

        return value.strip().upper()

    @field_validator(
        "motivo",
        mode="before",
    )
    @classmethod
    def normalizar_motivo(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza el motivo de ausencia o justificación.
        """

        return _normalizar_texto_opcional(value)

    @field_validator(
        "motivo_regularizacion",
    )
    @classmethod
    def normalizar_motivo_regularizacion(
        cls,
        value: str,
    ) -> str:
        """
        Garantiza que el motivo administrativo tenga contenido.
        """

        value = value.strip()

        if not value:
            raise ValueError(
                "El motivo de regularización es obligatorio."
            )

        return value

    @model_validator(mode="after")
    def validar_reglas_regularizacion(
        self,
    ) -> "AsistenciaRegularizacionRequest":
        """
        Valida las reglas asociadas al estado informado.
        """

        estados_permitidos = {
            "PRESENTE",
            "AUSENTE",
            "JUSTIFICADA",
        }

        if self.estado not in estados_permitidos:
            raise ValueError(
                "El estado debe ser PRESENTE, AUSENTE o JUSTIFICADA."
            )

        if (
            self.estado in {
                "AUSENTE",
                "JUSTIFICADA",
            }
            and not self.motivo
        ):
            raise ValueError(
                "AUSENTE y JUSTIFICADA requieren motivo."
            )

        if self.estado == "PRESENTE":
            self.motivo = None

        return self


# ============================================================
# ASISTENCIA - RESPUESTA API
# ============================================================


class AsistenciaSummary(BaseModel):
    """
    Información de una asistencia asociada a una participación.

    DATOS TÉCNICOS:
    - latitud;
    - longitud;
    - precisión GPS;
    - fecha de geolocalización.

    DATOS LEGIBLES:
    - dirección detectada;
    - comuna detectada;
    - región detectada.

    Los datos legibles son informativos y no reemplazan
    las coordenadas originales.
    """

    id: UUID
    asignacion_participante_id: UUID

    estado: str

    motivo: str | None = None

    latitud: float | None = None
    longitud: float | None = None

    precision_gps: float | None = None

    fecha_geolocalizacion: datetime | None = None

    direccion_detectada: str | None = None
    comuna_detectada: str | None = None
    region_detectada: str | None = None

    informado_por: UUID | None = None
    fecha_informe: datetime | None = None

    motivo_regularizacion: str | None = None

    created_at: datetime
    updated_at: datetime


# ============================================================
# CONTACTOS - CREACIÓN
# ============================================================


class ContactoAsignacionCreate(BaseModel):
    """
    Contacto/profesor que será asociado a una asignación escolar.
    """

    contacto_colegio_id: UUID


# ============================================================
# CONTACTOS - RESPUESTA API
# ============================================================


class ContactoAsignacionSummary(BaseModel):
    """
    Relación entre una asignación y un contacto del colegio.
    """

    id: UUID
    contacto_colegio_id: UUID


# ============================================================
# CREACIÓN DE ASIGNACIÓN
# ============================================================


class AsignacionCreate(BaseModel):
    """
    Payload para crear una asignación.

    Las reglas específicas de obligatoriedad dependen del tipo
    de actividad y son validadas posteriormente por el backend.
    """

    tipo_actividad_id: UUID

    colegio_id: UUID | None = None
    curso_colegio_id: UUID | None = None
    sala_id: UUID | None = None
    ramo_id: UUID | None = None

    espacio_reflexion_id: UUID | None = None
    espacio_encuentro_id: UUID | None = None

    fecha: date
    hora_inicio: time
    hora_fin: time

    lugar: str | None = Field(
        default=None,
        max_length=250,
    )

    observacion: str | None = Field(
        default=None,
        max_length=2000,
    )

    participantes: list[ParticipanteCreate] = Field(
        ...,
        min_length=1,
    )

    contactos: list[ContactoAsignacionCreate] = Field(
        default_factory=list,
        max_length=2,
    )

    @field_validator(
        "lugar",
        "observacion",
        mode="before",
    )
    @classmethod
    def normalizar_textos(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza textos opcionales antes de las validaciones.
        """

        return _normalizar_texto_opcional(value)

    @model_validator(mode="after")
    def validar_horario(
        self,
    ) -> "AsignacionCreate":
        """
        La hora de término siempre debe ser posterior
        a la hora de inicio.
        """

        if self.hora_fin <= self.hora_inicio:
            raise ValueError(
                "hora_fin debe ser posterior a hora_inicio."
            )

        return self

    @model_validator(mode="after")
    def validar_participantes_duplicados(
        self,
    ) -> "AsignacionCreate":
        """
        Un usuario solo puede aparecer una vez por asignación.
        """

        usuarios = [
            participante.usuario_id
            for participante in self.participantes
        ]

        if len(usuarios) != len(set(usuarios)):
            raise ValueError(
                "No se permite repetir un participante "
                "dentro de la misma asignación."
            )

        return self

    @model_validator(mode="after")
    def validar_contactos_duplicados(
        self,
    ) -> "AsignacionCreate":
        """
        Un mismo contacto no puede asociarse dos veces
        a una asignación.
        """

        contactos = [
            contacto.contacto_colegio_id
            for contacto in self.contactos
        ]

        if len(contactos) != len(set(contactos)):
            raise ValueError(
                "No se permite repetir un contacto "
                "dentro de la misma asignación."
            )

        return self


# ============================================================
# ACTUALIZACIÓN PARCIAL DE ASIGNACIÓN
# ============================================================


class AsignacionUpdate(BaseModel):
    """
    Payload para actualizar parcialmente una asignación existente.

    Este schema modela únicamente los datos editables de la asignación.
    No permite modificar:
    - tipo_actividad_id, porque el tipo queda fijo después de crearla;
    - estado_id, porque los cambios de estado siguen reglas de negocio
      específicas y no se reciben libremente desde frontend;
    - participantes, porque su gestión pertenece a un flujo separado.

    IMPORTANTE:
    - que un campo no venga en el payload significa "mantener valor actual";
    - que un campo venga explícitamente como None significa "intentar limpiar
      ese valor";
    - el backend debe distinguir ambos casos usando model_fields_set;
    - la validez final de None depende del tipo de actividad y debe comprobarse
      contra el estado completo resultante de la asignación;
    - las reglas de cambios críticos/no críticos se validan en el endpoint,
      porque dependen del estado actual, fecha/hora y rol autenticado.
    """

    model_config = ConfigDict(extra="forbid")

    colegio_id: UUID | None = None
    curso_colegio_id: UUID | None = None
    sala_id: UUID | None = None
    ramo_id: UUID | None = None

    espacio_reflexion_id: UUID | None = None
    espacio_encuentro_id: UUID | None = None

    fecha: date | None = None
    hora_inicio: time | None = None
    hora_fin: time | None = None

    lugar: str | None = Field(
        default=None,
        max_length=250,
    )

    observacion: str | None = Field(
        default=None,
        max_length=2000,
    )

    contactos: list[ContactoAsignacionCreate] | None = Field(
        default=None,
        max_length=2,
    )

    @field_validator(
        "lugar",
        "observacion",
        mode="before",
    )
    @classmethod
    def normalizar_textos(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza textos editables sin decidir si pueden quedar vacíos.

        La obligatoriedad final depende del tipo de actividad actual y se
        valida después de combinar el payload con los valores persistidos.
        """

        return _normalizar_texto_opcional(value)

    @model_validator(mode="after")
    def validar_horario_si_viene_completo(
        self,
    ) -> "AsignacionUpdate":
        """
        Valida el horario solo cuando inicio y fin vienen juntos en el PATCH.

        Si llega únicamente uno de los dos campos, la comparación debe hacerse
        en el backend contra el valor actual almacenado. Hacerlo aquí obligaría
        a conocer información que este schema parcial no posee.
        """

        if (
            self.hora_inicio is not None
            and self.hora_fin is not None
            and self.hora_fin <= self.hora_inicio
        ):
            raise ValueError(
                "hora_fin debe ser posterior a hora_inicio."
            )

        return self

    @model_validator(mode="after")
    def validar_contactos_duplicados(
        self,
    ) -> "AsignacionUpdate":
        """
        Evita contactos duplicados cuando el PATCH reemplaza esa relación.

        La cantidad mínima y la pertenencia al colegio se validan en backend,
        porque dependen del tipo de actividad y del colegio resultante.
        """

        if self.contactos is None:
            return self

        contactos = [
            contacto.contacto_colegio_id
            for contacto in self.contactos
        ]

        if len(contactos) != len(set(contactos)):
            raise ValueError(
                "No se permite repetir un contacto "
                "dentro de la misma asignación."
            )

        return self


# ============================================================
# LISTADO DE ASIGNACIONES
# ============================================================


class AsignacionListItem(BaseModel):
    """
    Información utilizada en el listado general de asignaciones.
    """

    id: UUID
    tipo_actividad_id: UUID

    colegio_id: UUID | None = None
    curso_colegio_id: UUID | None = None
    sala_id: UUID | None = None
    ramo_id: UUID | None = None

    espacio_reflexion_id: UUID | None = None
    espacio_encuentro_id: UUID | None = None

    fecha: date
    hora_inicio: time
    hora_fin: time

    lugar: str | None = None
    observacion: str | None = None

    estado_id: UUID

    activo: bool

    created_at: datetime
    updated_at: datetime


# ============================================================
# DETALLE DE ASIGNACIÓN
# ============================================================


class AsignacionDetail(AsignacionListItem):
    """
    Detalle completo de una asignación.

    Incluye:
    - participantes activos;
    - contactos/profesores asociados.
    """

    participantes: list[ParticipanteSummary] = Field(
        default_factory=list
    )

    contactos: list[ContactoAsignacionSummary] = Field(
        default_factory=list
    )