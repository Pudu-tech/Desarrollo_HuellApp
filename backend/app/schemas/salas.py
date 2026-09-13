from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


def _normalize_required_text(
    value: str,
    field_name: str,
) -> str:
    """
    Normaliza un texto obligatorio.

    Elimina espacios al inicio y al final y valida
    que el valor no quede vacío.
    """

    normalized = value.strip()

    if not normalized:
        raise ValueError(
            f"{field_name} no puede estar vacío."
        )

    return normalized


def _normalize_optional_text(
    value: str | None,
) -> str | None:
    """
    Normaliza textos opcionales.

    Los valores vacíos o compuestos solo por espacios
    se convierten en None.
    """

    if value is None:
        return None

    normalized = value.strip()

    return normalized or None


class SalaListItem(BaseModel):
    """
    Representación pública de una sala.
    """

    id: UUID
    colegio_id: UUID
    nombre: str
    descripcion: str | None
    capacidad: int | None
    ubicacion: str | None
    activo: bool
    created_at: datetime
    updated_at: datetime


class SalaCreate(BaseModel):
    """
    Datos permitidos para crear una sala.

    La sala siempre debe pertenecer a un colegio.
    """

    colegio_id: UUID

    nombre: str = Field(
        ...,
        min_length=1,
        max_length=150,
        description="Nombre de la sala.",
        examples=["Sala 1"],
    )

    descripcion: str | None = Field(
        default=None,
        max_length=500,
        description="Descripción opcional de la sala.",
    )

    capacidad: int | None = Field(
        default=None,
        ge=1,
        le=1000,
        description="Capacidad máxima de personas.",
        examples=[30],
    )

    ubicacion: str | None = Field(
        default=None,
        max_length=200,
        description="Ubicación física de la sala.",
        examples=["Segundo piso"],
    )

    @field_validator("nombre", mode="before")
    @classmethod
    def validate_nombre(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza y valida el nombre obligatorio.
        """

        if not isinstance(value, str):
            raise ValueError(
                "El nombre de la sala debe ser texto."
            )

        return _normalize_required_text(
            value,
            "El nombre",
        )

    @field_validator(
        "descripcion",
        "ubicacion",
        mode="before",
    )
    @classmethod
    def normalize_optional_text(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Convierte textos opcionales vacíos en None.
        """

        if value is not None and not isinstance(value, str):
            raise ValueError(
                "El valor debe ser texto."
            )

        return _normalize_optional_text(value)


class SalaUpdate(BaseModel):
    """
    Datos permitidos para actualizar una sala.

    Todos los campos son opcionales porque PATCH
    permite actualizaciones parciales.
    """

    colegio_id: UUID | None = None

    nombre: str | None = Field(
        default=None,
        min_length=1,
        max_length=150,
        description="Nombre de la sala.",
    )

    descripcion: str | None = Field(
        default=None,
        max_length=500,
        description="Descripción opcional.",
    )

    capacidad: int | None = Field(
        default=None,
        ge=1,
        le=1000,
        description="Capacidad máxima de personas.",
    )

    ubicacion: str | None = Field(
        default=None,
        max_length=200,
        description="Ubicación física de la sala.",
    )

    @field_validator("colegio_id", mode="before")
    @classmethod
    def validate_colegio_id(
        cls,
        value,
    ):
        """
        Evita que colegio_id sea enviado explícitamente como null.

        Si no se desea modificar, el campo debe omitirse.
        """

        if value is None:
            raise ValueError(
                "colegio_id no puede enviarse como null. "
                "Omita el campo si no desea modificarlo."
            )

        return value

    @field_validator("nombre", mode="before")
    @classmethod
    def validate_nombre(
        cls,
        value: str | None,
    ) -> str:
        """
        Valida el nombre cuando se incluye en PATCH.
        """

        if value is None:
            raise ValueError(
                "El nombre no puede enviarse como null. "
                "Omita el campo si no desea modificarlo."
            )

        if not isinstance(value, str):
            raise ValueError(
                "El nombre de la sala debe ser texto."
            )

        return _normalize_required_text(
            value,
            "El nombre",
        )

    @field_validator(
        "descripcion",
        "ubicacion",
        mode="before",
    )
    @classmethod
    def normalize_optional_text(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Permite limpiar descripcion y ubicacion enviando null
        o una cadena vacía.
        """

        if value is not None and not isinstance(value, str):
            raise ValueError(
                "El valor debe ser texto."
            )

        return _normalize_optional_text(value)