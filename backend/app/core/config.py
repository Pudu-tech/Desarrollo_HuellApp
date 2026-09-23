"""
Configuración central del backend de HuellAPP.

Este módulo se encarga de cargar y validar las variables de entorno
utilizadas por la aplicación.

SECURITY:
- No deben existir credenciales escritas directamente en este archivo.
- Los secretos deben almacenarse únicamente en variables de entorno.
- La clave secreta de Supabase es exclusiva del backend y nunca debe
  exponerse al frontend, logs públicos ni repositorios.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Representa la configuración principal de HuellAPP.

    Pydantic valida automáticamente la existencia y el tipo de las
    variables requeridas antes de que la aplicación las utilice.
    """

    app_name: str = "HuellAPP API"
    app_env: str = "development"

    supabase_url: str
    supabase_secret_key: str

    # Se configura desde entorno para no hardcodear dominios de
    # desarrollo, QA o producción dentro de la aplicación.
    cors_origins: list[str] = ["http://localhost:5173"]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def is_production(self) -> bool:
        """Indica si la aplicación se está ejecutando en producción."""

        return self.app_env.strip().lower() == "production"


@lru_cache
def get_settings() -> Settings:
    """
    Retorna una instancia cacheada de la configuración.

    El uso de cache evita leer y validar repetidamente el archivo
    de variables de entorno durante la ejecución de la API.
    """

    return Settings()
