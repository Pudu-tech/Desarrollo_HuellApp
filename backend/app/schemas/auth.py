"""
Esquemas de datos relacionados con autenticación en HuellAPP.

Este módulo define las estructuras que utilizará FastAPI para:
- representar información del usuario autenticado;
- validar datos derivados del token de Supabase;
- mantener tipado consistente entre endpoints y servicios.

SECURITY:
- Este archivo no almacena contraseñas, tokens ni secretos.
- Los esquemas representan únicamente datos ya validados
  por los mecanismos de autenticación del backend.
"""

from uuid import UUID

from pydantic import BaseModel, EmailStr


class AuthenticatedUser(BaseModel):
    """
    Representa al usuario autenticado dentro de HuellAPP.

    Attributes:
        id:
            UUID único del usuario, compartido con auth.users.

        email:
            Correo utilizado para autenticación.

        nombres:
            Nombres reales registrados en public.usuarios.

        apellido_paterno:
            Apellido paterno registrado en public.usuarios.

        role_code:
            Código del rol actual del usuario.
    """

    id: UUID
    email: EmailStr
    nombres: str
    apellido_paterno: str
    role_code: str