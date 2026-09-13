"""
Cliente central de Supabase para el backend de HuellAPP.

Este módulo crea una única instancia reutilizable del cliente de Supabase
utilizando las variables de entorno definidas en `config.py`.

SECURITY:
- La clave secreta de Supabase solo debe utilizarse en el backend.
- Nunca debe exponerse en React, logs, repositorios o respuestas HTTP.
- Este cliente utiliza privilegios elevados, por lo que cualquier acceso
  a datos debe pasar por validaciones de permisos y reglas de negocio.
"""

from functools import lru_cache

from supabase import Client, create_client

from app.core.config import get_settings


@lru_cache
def get_supabase_client() -> Client:
    """
    Crea y retorna una instancia cacheada del cliente de Supabase.

    La instancia se reutiliza durante la ejecución de la aplicación para
    evitar crear un cliente nuevo en cada solicitud.

    Returns:
        Client: Cliente configurado para acceder a Supabase desde FastAPI.
    """

    settings = get_settings()

    return create_client(
        settings.supabase_url,
        settings.supabase_secret_key,
    )