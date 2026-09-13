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

    Esta estructura se utilizará después de validar el JWT emitido
    por Supabase Auth y obtener el perfil correspondiente desde
    la tabla `usuarios`.

    Attributes:
        id: UUID único del usuario, compartido con auth.users.
        email: Correo utilizado para autenticación.
        role_code: Código del rol actual del usuario.
    """

    id: UUID
    email: EmailStr
    role_code: str