"""HuellApp · Contratos de coordinación por colegio.

RESPONSABILIDADES
------------------------------------------------------------
- Tipar las asociaciones entre coordinadores, colegios y monitores.
- Representar advertencias de multi-colegio sin delegar autorización al frontend.

SECURITY
------------------------------------------------------------
Los IDs enviados por el cliente se validan en backend y nuevamente en las RPC.
El frontend nunca decide permisos ni puede omitir la confirmación excepcional.
"""

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ColegioReferencia(BaseModel):
    """Referencia mínima de un colegio asociado a un coordinador."""

    id: UUID
    nombre: str


class CoordinadorColegioAsignacionRequest(BaseModel):
    """Solicitud para asociar un coordinador a un colegio."""

    model_config = ConfigDict(extra="forbid")

    coordinador_id: UUID
    confirmar_multi_colegio: bool = False


class CoordinadorColegioItem(BaseModel):
    """Coordinador visible dentro de la ficha de un colegio."""

    relation_id: UUID
    coordinador_id: UUID
    nombres: str
    apellido_paterno: str
    apellido_materno: str | None = None
    email: str
    activo: bool
    otros_colegios: list[ColegioReferencia] = Field(default_factory=list)


class MonitorCoordinadorAsignacionRequest(BaseModel):
    """Solicitud para asociar un monitor al coordinador dentro de un colegio."""

    model_config = ConfigDict(extra="forbid")

    monitor_id: UUID


class MonitorCoordinadorItem(BaseModel):
    """Monitor asociado a un coordinador dentro de un colegio."""

    relation_id: UUID
    monitor_id: UUID
    nombres: str
    apellido_paterno: str
    apellido_materno: str | None = None
    email: str
    activo: bool


class UsuarioCoordinacionItem(BaseModel):
    """Usuario activo elegible para una relación de coordinación."""

    id: UUID
    nombres: str
    apellido_paterno: str
    apellido_materno: str | None = None
    email: str


class PanelMonitores(BaseModel):
    asignados: list[MonitorCoordinadorItem]
    candidatos: list[UsuarioCoordinacionItem]
