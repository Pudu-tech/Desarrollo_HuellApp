"""
Esquemas de datos relacionados con usuarios en HuellAPP.

Estos modelos definen la información que puede entrar y salir
del backend para operaciones relacionadas con usuarios.

SECURITY:
- No se exponen contraseñas en respuestas.
- Los datos de entrada se validan con Pydantic.
- Los roles recibidos desde el frontend son posteriormente
  validados por reglas de negocio en FastAPI.
"""

from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.core.validators import is_valid_chilean_rut


class UserRoleSummary(BaseModel):
    """
    Información básica del rol asociado a un usuario.
    """

    codigo: str
    nombre: str


class UserListItem(BaseModel):
    """
    Representación de un usuario dentro del listado administrativo.
    """

    id: UUID
    rut: str
    nombres: str
    apellido_paterno: str
    apellido_materno: str
    email: EmailStr
    telefono: str | None = None
    activo: bool
    roles: UserRoleSummary


class UserCreate(BaseModel):
    """
    Datos requeridos para crear un nuevo usuario.

    La contraseña se utiliza únicamente para crear la identidad
    en Supabase Auth y nunca debe almacenarse en public.usuarios.
    """

    rut: str = Field(
        min_length=3,
        max_length=12,
        description="RUT chileno sin puntos y con guion.",
    )

    nombres: str = Field(
        min_length=2,
        max_length=100,
    )

    apellido_paterno: str = Field(
        min_length=2,
        max_length=100,
    )

    apellido_materno: str = Field(
        min_length=2,
        max_length=100,
    )

    email: EmailStr

    telefono: str | None = Field(
        default=None,
        max_length=30,
    )

    role_code: str = Field(
        min_length=3,
        max_length=50,
        description="Código del rol solicitado.",
    )

    password: str = Field(
        min_length=8,
        max_length=128,
        description="Contraseña inicial del usuario.",
    )

    @field_validator("rut")
    @classmethod
    def normalize_and_validate_rut(cls, value: str) -> str:
        """
        Normaliza y valida un RUT chileno.

        Elimina puntos y espacios, convierte el dígito verificador
        a mayúscula y valida matemáticamente el dígito verificador.

        Ejemplo:
            15.766.669-6 -> 15766669-6
        """

        normalized = (
            value.replace(".", "")
            .replace(" ", "")
            .upper()
            .strip()
        )

        if not is_valid_chilean_rut(normalized):
            raise ValueError("El RUT ingresado no es válido.")

        return normalized

    @field_validator("nombres", "apellido_paterno", "apellido_materno")
    @classmethod
    def normalize_person_name(cls, value: str) -> str:
        """
        Elimina espacios innecesarios en campos de nombre.
        """

        return " ".join(value.strip().split())

    @field_validator("role_code")
    @classmethod
    def normalize_role_code(cls, value: str) -> str:
        """
        Normaliza el código de rol para comparaciones consistentes.
        """

        return value.strip().upper()

    @field_validator("telefono")
    @classmethod
    def normalize_phone(cls, value: str | None) -> str | None:
        """
        Normaliza el teléfono eliminando espacios innecesarios.

        Si no se entrega un teléfono, mantiene el valor en None.
        """

        if value is None:
            return None

        normalized = value.strip()

        return normalized or None


class UserCreateResponse(BaseModel):
    """
    Respuesta entregada después de crear correctamente un usuario.

    SECURITY:
    La contraseña nunca forma parte de la respuesta.
    """

    id: UUID
    rut: str
    nombres: str
    apellido_paterno: str
    apellido_materno: str
    email: EmailStr
    telefono: str | None = None
    activo: bool
    roles: UserRoleSummary

class UserUpdate(BaseModel):
    """
    Datos permitidos para editar información básica de un usuario.

    Todos los campos son opcionales para permitir actualizaciones
    parciales mediante PATCH.

    SECURITY:
    - No permite modificar rol.
    - No permite modificar estado.
    - No permite modificar correo.
    - No permite modificar contraseña.
    """

    nombres: str | None = Field(
        default=None,
        min_length=2,
        max_length=100,
    )

    apellido_paterno: str | None = Field(
        default=None,
        min_length=2,
        max_length=100,
    )

    apellido_materno: str | None = Field(
        default=None,
        min_length=2,
        max_length=100,
    )

    telefono: str | None = Field(
        default=None,
        max_length=30,
    )

    @field_validator(
        "nombres",
        "apellido_paterno",
        "apellido_materno",
    )
    @classmethod
    def normalize_optional_person_name(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza nombres opcionales cuando son enviados.
        """

        if value is None:
            return None

        return " ".join(value.strip().split())

    @field_validator("telefono")
    @classmethod
    def normalize_optional_phone(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza el teléfono opcional.
        """

        if value is None:
            return None

        normalized = value.strip()

        return normalized or None
    
class UserRoleUpdate(BaseModel):
    """
    Datos requeridos para cambiar el rol de un usuario.

    SECURITY:
    - El rol solicitado se valida posteriormente en backend.
    - No se confía en códigos enviados por el frontend.
    """

    role_code: str = Field(
        min_length=3,
        max_length=50,
        description="Código del nuevo rol del usuario.",
    )

    @field_validator("role_code")
    @classmethod
    def normalize_role_code(cls, value: str) -> str:
        """
        Normaliza el código del rol para comparaciones consistentes.
        """

        return value.strip().upper()