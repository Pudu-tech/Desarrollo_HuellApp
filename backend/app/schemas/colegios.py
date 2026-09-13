"""
Schemas utilizados para la administración de colegios en HuellAPP.

Estos modelos definen:
- los datos permitidos para crear colegios;
- los datos permitidos para actualizar colegios;
- la estructura de respuesta retornada por la API.

SECURITY:
- created_by y updated_by son determinados exclusivamente por el backend.
- activo y deleted_at no pueden manipularse desde los endpoints generales.
- Los campos obligatorios no pueden reemplazarse por valores null o vacíos.
- Los textos se normalizan antes de llegar a la base de datos.
"""

from uuid import UUID

from pydantic import BaseModel, EmailStr, field_validator


# ============================================================
# FUNCIONES DE NORMALIZACIÓN
# ============================================================


def _normalizar_texto_obligatorio(value: str) -> str:
    """
    Normaliza un texto obligatorio.

    Elimina espacios al inicio y al final y evita almacenar
    cadenas vacías.
    """

    normalized = value.strip()

    if not normalized:
        raise ValueError("El campo no puede estar vacío.")

    return normalized


def _normalizar_texto_opcional(
    value: str | None,
) -> str | None:
    """
    Normaliza un texto opcional.

    Los textos vacíos se convierten en None.
    """

    if value is None:
        return None

    normalized = value.strip()

    return normalized if normalized else None


# ============================================================
# RESPUESTA
# ============================================================


class ColegioListItem(BaseModel):
    """
    Representa un colegio retornado por la API.
    """

    id: UUID

    rbd: str | None = None
    nombre: str
    descripcion: str | None = None

    tipo_dependencia_id: UUID | None = None

    direccion: str
    numero: str | None = None
    complemento: str | None = None

    comuna_id: UUID
    region_id: UUID

    codigo_postal: str | None = None

    telefono: str | None = None
    email: EmailStr | None = None
    sitio_web: str | None = None

    nombre_contacto: str | None = None
    telefono_contacto: str | None = None
    email_contacto: EmailStr | None = None

    activo: bool


# ============================================================
# CREACIÓN
# ============================================================


class ColegioCreate(BaseModel):
    """
    Datos permitidos para crear un colegio.

    Los campos administrativos y de auditoría son controlados
    exclusivamente por el backend.
    """

    rbd: str | None = None
    nombre: str
    descripcion: str | None = None

    tipo_dependencia_id: UUID | None = None

    direccion: str
    numero: str | None = None
    complemento: str | None = None

    comuna_id: UUID
    region_id: UUID

    codigo_postal: str | None = None

    telefono: str | None = None
    email: EmailStr | None = None
    sitio_web: str | None = None

    nombre_contacto: str | None = None
    telefono_contacto: str | None = None
    email_contacto: EmailStr | None = None

    @field_validator(
        "nombre",
        "direccion",
        mode="before",
    )
    @classmethod
    def normalizar_campos_obligatorios(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza campos obligatorios.
        """

        if not isinstance(value, str):
            raise ValueError("El valor debe ser texto.")

        return _normalizar_texto_obligatorio(value)

    @field_validator(
        "rbd",
        "descripcion",
        "numero",
        "complemento",
        "codigo_postal",
        "telefono",
        "sitio_web",
        "nombre_contacto",
        "telefono_contacto",
        mode="before",
    )
    @classmethod
    def normalizar_campos_opcionales(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza campos opcionales.
        """

        return _normalizar_texto_opcional(value)


# ============================================================
# ACTUALIZACIÓN
# ============================================================


class ColegioUpdate(BaseModel):
    """
    Datos permitidos para modificar un colegio.

    Todos los campos son opcionales porque PATCH modifica
    únicamente aquellos enviados por el cliente.

    Importante:
    - nombre y direccion pueden omitirse;
    - pero si son enviados no pueden ser null ni quedar vacíos.
    """

    rbd: str | None = None
    nombre: str | None = None
    descripcion: str | None = None

    tipo_dependencia_id: UUID | None = None

    direccion: str | None = None
    numero: str | None = None
    complemento: str | None = None

    comuna_id: UUID | None = None
    region_id: UUID | None = None

    codigo_postal: str | None = None

    telefono: str | None = None
    email: EmailStr | None = None
    sitio_web: str | None = None

    nombre_contacto: str | None = None
    telefono_contacto: str | None = None
    email_contacto: EmailStr | None = None

    @field_validator(
        "nombre",
        "direccion",
        mode="before",
    )
    @classmethod
    def validar_campos_obligatorios_si_se_envian(
        cls,
        value: str | None,
    ) -> str:
        """
        Evita reemplazar nombre o dirección por null o texto vacío.
        """

        if value is None:
            raise ValueError(
                "El campo no puede ser null."
            )

        if not isinstance(value, str):
            raise ValueError("El valor debe ser texto.")

        return _normalizar_texto_obligatorio(value)

    @field_validator(
        "rbd",
        "descripcion",
        "numero",
        "complemento",
        "codigo_postal",
        "telefono",
        "sitio_web",
        "nombre_contacto",
        "telefono_contacto",
        mode="before",
    )
    @classmethod
    def normalizar_campos_opcionales(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza campos opcionales enviados mediante PATCH.
        """

        return _normalizar_texto_opcional(value)