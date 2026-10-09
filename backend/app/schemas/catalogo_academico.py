"""Contratos del catálogo global; actor, estado y auditoría no vienen del cliente."""
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, model_validator


class RecursoAcademicoDatos(BaseModel):
    """Datos completos de edición; asignatura con niveles o espacio con padre."""
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    nombre: str = Field(min_length=1, max_length=150)
    descripcion: str | None = Field(default=None, max_length=2000)
    nivel_ids: list[UUID] | None = Field(default=None, min_length=1, max_length=100)
    ramo_id: UUID | None = None
    orden: int | None = Field(default=None, ge=0, le=9999)

    @model_validator(mode="after")
    def validar_contexto(self):
        if self.nivel_ids is not None:
            if self.ramo_id is not None or self.orden is not None or len(set(self.nivel_ids)) != len(self.nivel_ids):
                raise ValueError("Una asignatura requiere niveles únicos y no recibe ramo ni orden.")
        elif self.ramo_id is None:
            raise ValueError("Un espacio requiere su asignatura.")
        return self


class RecursoAcademicoItem(BaseModel):
    """Estado confirmado por la base de datos, sin exponer metadatos de cuenta."""
    id: UUID
    nombre: str
    descripcion: str | None = None
    activo: bool
    nivel_ids: list[UUID] = Field(default_factory=list)
    ramo_id: UUID | None = None
    orden: int | None = None


class NivelAcademicoItem(BaseModel):
    id: UUID
    nombre: str
    activo: bool


class CatalogoAcademico(BaseModel):
    niveles: list[NivelAcademicoItem]
    asignaturas: list[RecursoAcademicoItem]
    reflexion: list[RecursoAcademicoItem]
    encuentro: list[RecursoAcademicoItem]
