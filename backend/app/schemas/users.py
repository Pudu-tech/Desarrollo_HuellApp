"""
Esquemas de datos relacionados con usuarios en HuellAPP.

Estos modelos definen la información que puede entrar y salir
del backend para operaciones relacionadas con usuarios.

SECURITY
------------------------------------------------------------
- No se reciben ni exponen contraseñas durante la creación.
- Los usuarios nuevos configuran su propia contraseña mediante
  el flujo de invitación de Supabase Auth.
- Los datos de entrada se validan con Pydantic.
- Los roles recibidos desde el frontend son posteriormente
  validados por reglas de negocio en FastAPI.
- Las reglas de autorización definitivas permanecen en backend.
"""

from uuid import UUID

from pydantic import (
    BaseModel,
    EmailStr,
    Field,
    field_validator,
)

from app.core.validators import is_valid_chilean_rut


# ============================================================
# RESUMEN DE ROL
# ============================================================


class UserRoleSummary(BaseModel):
    """
    Información básica del rol asociado a un usuario.

    Se utiliza principalmente en respuestas administrativas
    para evitar exponer información innecesaria del rol.
    """

    codigo: str
    nombre: str


# ============================================================
# LISTADO DE USUARIOS
# ============================================================


class UserListItem(BaseModel):
    """
    Representación pública de un usuario dentro del listado
    administrativo de HuellAPP.

    SECURITY
    --------------------------------------------------------
    Este modelo no contiene credenciales ni información
    sensible de autenticación.
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


# ============================================================
# CREACIÓN / INVITACIÓN DE USUARIO
# ============================================================


class UserCreate(BaseModel):
    """
    Datos requeridos para crear e invitar un nuevo usuario.

    FLUJO
    --------------------------------------------------------
    El administrador registra los datos personales y el rol.

    El backend posteriormente solicita a Supabase Auth el envío
    de una invitación al correo registrado.

    El usuario invitado será responsable de establecer su propia
    contraseña mediante el flujo de activación correspondiente.

    SECURITY
    --------------------------------------------------------
    El administrador nunca define, conoce ni transmite la
    contraseña inicial del usuario.
    """

    rut: str = Field(
        min_length=3,
        max_length=12,
        description="RUT chileno sin puntos y con guion.",
    )

    nombres: str = Field(
        min_length=2,
        max_length=100,
        description="Nombres del usuario.",
    )

    apellido_paterno: str = Field(
        min_length=2,
        max_length=100,
        description="Apellido paterno del usuario.",
    )

    apellido_materno: str = Field(
        min_length=2,
        max_length=100,
        description="Apellido materno del usuario.",
    )

    email: EmailStr = Field(
        description=(
            "Correo electrónico al cual se enviará "
            "la invitación de acceso."
        ),
    )

    telefono: str | None = Field(
        default=None,
        max_length=30,
        description="Teléfono de contacto opcional.",
    )

    role_code: str = Field(
        min_length=3,
        max_length=50,
        description="Código del rol solicitado.",
    )

    @field_validator("rut")
    @classmethod
    def normalize_and_validate_rut(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza y valida un RUT chileno.

        Operaciones realizadas:
        - elimina puntos;
        - elimina espacios;
        - convierte el dígito verificador a mayúscula;
        - valida matemáticamente el RUT.

        Ejemplo:
            15.766.669-6 -> 15766669-6
        """

        normalized = (
            value
            .replace(".", "")
            .replace(" ", "")
            .upper()
            .strip()
        )

        if not is_valid_chilean_rut(normalized):
            raise ValueError(
                "El RUT ingresado no es válido."
            )

        return normalized

    @field_validator(
        "nombres",
        "apellido_paterno",
        "apellido_materno",
    )
    @classmethod
    def normalize_person_name(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza nombres y apellidos.

        Elimina espacios al inicio/final y reduce múltiples
        espacios internos a uno solo.
        """

        return " ".join(
            value.strip().split()
        )

    @field_validator("role_code")
    @classmethod
    def normalize_role_code(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza el código de rol.

        El rol se convierte a mayúsculas para mantener
        comparaciones consistentes en las reglas de negocio.
        """

        return value.strip().upper()

    @field_validator("telefono")
    @classmethod
    def normalize_phone(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza el teléfono opcional.

        Si el valor contiene únicamente espacios se almacena
        conceptualmente como None.
        """

        if value is None:
            return None

        normalized = value.strip()

        return normalized or None


# ============================================================
# RESPUESTA DE CREACIÓN
# ============================================================


class UserCreateResponse(BaseModel):
    """
    Respuesta entregada después de crear e invitar
    correctamente un usuario.

    SECURITY
    --------------------------------------------------------
    No contiene contraseñas, tokens, secretos ni información
    interna de Supabase Auth.
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


# ============================================================
# EDICIÓN DE DATOS BÁSICOS
# ============================================================


class UserUpdate(BaseModel):
    """
    Datos permitidos para editar información básica
    de un usuario.

    Todos los campos son opcionales para permitir
    actualizaciones parciales mediante PATCH.

    SECURITY
    --------------------------------------------------------
    Este esquema no permite modificar:
    - rol;
    - estado;
    - correo electrónico;
    - contraseña;
    - identidad de Supabase Auth.

    Estas operaciones, cuando corresponda, deben poseer
    endpoints y reglas de autorización independientes.
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
        Normaliza nombres y apellidos cuando son enviados
        en una actualización parcial.
        """

        if value is None:
            return None

        return " ".join(
            value.strip().split()
        )

    @field_validator("telefono")
    @classmethod
    def normalize_optional_phone(
        cls,
        value: str | None,
    ) -> str | None:
        """
        Normaliza el teléfono durante una actualización.

        Un valor vacío se transforma en None.
        """

        if value is None:
            return None

        normalized = value.strip()

        return normalized or None


# ============================================================
# CAMBIO DE CORREO
# ============================================================


class UserEmailUpdate(BaseModel):
    """
    Datos requeridos para cambiar el correo de un usuario.

    SECURITY
    --------------------------------------------------------
    - El cambio se procesa mediante un endpoint independiente.
    - El backend coordina Supabase Auth y public.usuarios.
    - El mismo UUID del usuario se conserva.
    - El nuevo correo se valida antes de ejecutar el cambio.
    """

    email: EmailStr = Field(
        description="Nuevo correo electrónico del usuario.",
    )


# ============================================================
# CAMBIO DE ROL
# ============================================================


class UserRoleUpdate(BaseModel):
    """
    Datos requeridos para cambiar el rol de un usuario.

    SECURITY
    --------------------------------------------------------
    - El código recibido desde frontend nunca se considera
      automáticamente autorizado.
    - FastAPI debe validar que el rol exista.
    - FastAPI debe validar que el actor tenga permiso para
      asignar ese rol.
    """

    role_code: str = Field(
        min_length=3,
        max_length=50,
        description="Código del nuevo rol del usuario.",
    )

    @field_validator("role_code")
    @classmethod
    def normalize_role_code(
        cls,
        value: str,
    ) -> str:
        """
        Normaliza el código del rol para comparaciones
        consistentes en backend.
        """

        return value.strip().upper()
