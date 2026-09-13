from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


def _normalize_required_text(value: str, field_name: str) -> str:
    """
    Normaliza texto obligatorio eliminando espacios al inicio y final.

    Args:
        value: Valor recibido.
        field_name: Nombre lógico del campo para generar mensajes claros.

    Returns:
        Texto normalizado.

    Raises:
        ValueError: Si el valor viene vacío.
    """
    normalized = value.strip()

    if not normalized:
        raise ValueError(f"{field_name} no puede estar vacío.")

    return normalized


class CursoListItem(BaseModel):
    """
    Representación pública de un curso asociado a un colegio.
    """

    id: UUID
    colegio_id: UUID
    nivel_curso_id: UUID
    seccion: str
    nombre_mostrado: str
    anio: int
    activo: bool
    created_at: datetime
    updated_at: datetime


class CursoCreate(BaseModel):
    """
    Datos permitidos para crear un curso.

    nombre_mostrado no se recibe desde el cliente.
    El backend lo genera usando el nombre del nivel y la sección.
    """

    colegio_id: UUID
    nivel_curso_id: UUID

    seccion: str = Field(
        ...,
        min_length=1,
        max_length=1,
        description="Sección del curso entre A y Z.",
        examples=["A"],
    )

    anio: int = Field(
        ...,
        ge=2000,
        le=2100,
        description="Año académico del curso.",
        examples=[2026],
    )

    @field_validator("seccion", mode="before")
    @classmethod
    def validate_seccion(cls, value: str) -> str:
        """
        Normaliza y valida que la sección sea una única letra A-Z.
        """
        if not isinstance(value, str):
            raise ValueError("La sección debe ser una letra entre A y Z.")

        normalized = _normalize_required_text(value, "La sección").upper()

        if len(normalized) != 1 or not ("A" <= normalized <= "Z"):
            raise ValueError("La sección debe ser una única letra entre A y Z.")

        return normalized


class CursoUpdate(BaseModel):
    """
    Datos permitidos para modificar un curso.

    Todos los campos son opcionales porque PATCH admite actualizaciones
    parciales.

    nombre_mostrado tampoco puede ser modificado directamente por el cliente.
    El backend debe recalcularlo cuando cambia nivel_curso_id o seccion.
    """

    colegio_id: UUID | None = None
    nivel_curso_id: UUID | None = None

    seccion: str | None = Field(
        default=None,
        min_length=1,
        max_length=1,
        description="Sección del curso entre A y Z.",
    )

    anio: int | None = Field(
        default=None,
        ge=2000,
        le=2100,
        description="Año académico del curso.",
    )

    @field_validator("seccion", mode="before")
    @classmethod
    def validate_seccion(cls, value: str | None) -> str | None:
        """
        Normaliza y valida la sección cuando viene incluida en el PATCH.
        """
        if value is None:
            raise ValueError(
                "La sección no puede enviarse como null. "
                "Omita el campo si no desea modificarlo."
            )

        if not isinstance(value, str):
            raise ValueError("La sección debe ser una letra entre A y Z.")

        normalized = _normalize_required_text(value, "La sección").upper()

        if len(normalized) != 1 or not ("A" <= normalized <= "Z"):
            raise ValueError("La sección debe ser una única letra entre A y Z.")

        return normalized