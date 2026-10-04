"""HuellAPP | Contratos para contactos reutilizables de un colegio.

La tabla contactos_colegio constituye la fuente de contactos para Asignaciones.
Los identificadores, estado y auditoría no se aceptan desde el cliente.
Los apellidos opcionales respetan los registros anteriores a la migración 042.
"""
from uuid import UUID
from pydantic import BaseModel, ConfigDict, EmailStr, field_validator




def _validar_rut_chileno(value: str | None) -> str | None:
    """Normaliza y valida el dígito verificador de un RUT chileno opcional."""
    if value is None or not value.strip():
        return None
    limpio = value.upper().replace(".", "").replace("-", "").replace(" ", "")
    if len(limpio) < 2 or not limpio[:-1].isdigit() or limpio[-1] not in "0123456789K":
        raise ValueError("RUT inválido.")
    cuerpo, digito = limpio[:-1], limpio[-1]
    suma = sum(int(numero) * factor for numero, factor in
               zip(reversed(cuerpo), (2, 3, 4, 5, 6, 7) * 3))
    resto = 11 - suma % 11
    esperado = "0" if resto == 11 else "K" if resto == 10 else str(resto)
    if digito != esperado:
        raise ValueError("El dígito verificador del RUT no es válido.")
    return f"{int(cuerpo)}-{digito}"


class ContactoBase(BaseModel):
    """Datos de una persona; el RUT es opcional y se almacena normalizado."""
    nombre: str
    apellido_paterno: str | None = None
    apellido_materno: str | None = None
    rut: str | None = None
    email: EmailStr
    telefono: str
    cargo: str | None = None

    model_config = ConfigDict(extra="forbid")

    @field_validator("rut")
    @classmethod
    def rut_valido(cls, value: str | None) -> str | None:
        """Valida el RUT al crear un contacto; los históricos no se alteran."""
        return _validar_rut_chileno(value)

    @field_validator("nombre", "telefono")
    @classmethod
    def texto_obligatorio(cls, value: str) -> str:
        """Descarta valores vacíos sin modificar el significado del dato."""
        value = value.strip()
        if not value:
            raise ValueError("Este campo es obligatorio.")
        return value

    @field_validator("apellido_paterno", "apellido_materno", "cargo")
    @classmethod
    def texto_opcional(cls, value: str | None) -> str | None:
        """Convierte los opcionales vacíos en NULL, como exige la migración 042."""
        return value.strip() or None if value is not None else None


class ContactoCreate(ContactoBase):
    """Alta de contacto: nombre, email y teléfono obligatorios."""


class ContactoUpdate(BaseModel):
    """Modificación parcial; None limpia únicamente los campos opcionales."""
    nombre: str | None = None
    apellido_paterno: str | None = None
    apellido_materno: str | None = None
    rut: str | None = None
    email: EmailStr | None = None
    telefono: str | None = None
    cargo: str | None = None

    model_config = ConfigDict(extra="forbid")

    @field_validator("rut")
    @classmethod
    def rut_valido(cls, value: str | None) -> str | None:
        """Valida un RUT nuevo, sin exigirlo a los contactos históricos."""
        return _validar_rut_chileno(value)

    @field_validator("nombre", "telefono", "email")
    @classmethod
    def obligatorios_no_nulos(cls, value):
        """Impide limpiar campos de obligada presencia; PATCH omite los demás."""
        if value is None or (isinstance(value, str) and not value.strip()):
            raise ValueError("El campo no puede estar vacío.")
        return value.strip() if isinstance(value, str) else value

    @field_validator("apellido_paterno", "apellido_materno", "cargo")
    @classmethod
    def texto_opcional(cls, value: str | None) -> str | None:
        """Permite limpiar un campo opcional enviando null o cadena vacía."""
        return value.strip() or None if value is not None else None


class ContactoItem(ContactoBase):
    """Respuesta estable; una asignación referencia exclusivamente su UUID."""
    id: UUID
    colegio_id: UUID
    activo: bool
