"""
Configuración central del backend de HuellAPP.

Este módulo se encarga de cargar y validar las variables de entorno
utilizadas por la aplicación.

SECURITY
------------------------------------------------------------
- No deben existir credenciales escritas directamente en este archivo.
- Los secretos deben almacenarse únicamente en variables de entorno.
- La clave secreta de Supabase es exclusiva del backend y nunca debe
  exponerse al frontend, logs públicos ni repositorios.
- Las URLs y orígenes permitidos deben configurarse por ambiente.
"""

from functools import lru_cache

from pydantic_settings import (
    BaseSettings,
    SettingsConfigDict,
)


class Settings(BaseSettings):
    """
    Representa la configuración principal de HuellAPP.

    Pydantic carga automáticamente las variables desde el entorno
    y valida sus tipos antes de que la aplicación las utilice.

    La configuración permite mantener separados los ambientes
    local, DEV/QA y producción sin hardcodear valores específicos
    dentro de la lógica de negocio.
    """

    # ============================================================
    # APLICACIÓN
    # ============================================================

    app_name: str = "HuellAPP API"

    app_env: str = "development"

    # URL base del frontend asociada al ambiente actual.
    #
    # Ejemplos:
    #
    # Local:
    # http://localhost:5173
    #
    # DEV / QA:
    # https://huellapp-frontend-git-develop-huell-app.vercel.app
    #
    # PROD:
    # https://huellapp-frontend.vercel.app
    #
    # Se utiliza, entre otras cosas, para construir redirects
    # seguros de invitaciones y flujos de autenticación.
    frontend_url: str = "http://localhost:5173"

    # ============================================================
    # SUPABASE
    # ============================================================

    supabase_url: str

    # Clave secreta exclusiva del backend.
    #
    # Nunca debe utilizarse en el frontend ni almacenarse
    # dentro del repositorio.
    supabase_secret_key: str

    # ============================================================
    # CORS
    # ============================================================

    # Lista de orígenes autorizados para consumir la API.
    #
    # Se configura desde variables de entorno para evitar
    # hardcodear dominios de desarrollo, QA o producción.
    cors_origins: list[str] = [
        "http://localhost:5173",
    ]

    # ============================================================
    # CONFIGURACIÓN DE PYDANTIC SETTINGS
    # ============================================================

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ============================================================
    # PROPIEDADES DERIVADAS
    # ============================================================

    @property
    def is_production(self) -> bool:
        """
        Indica si la aplicación se está ejecutando
        en ambiente de producción.
        """

        return (
            self.app_env
            .strip()
            .lower()
            == "production"
        )

    @property
    def normalized_frontend_url(self) -> str:
        """
        Retorna la URL del frontend sin slash final.

        Esto evita errores al construir rutas dinámicas como:

            {frontend_url}/establecer-password
        """

        return self.frontend_url.rstrip("/")


@lru_cache
def get_settings() -> Settings:
    """
    Retorna una instancia cacheada de la configuración.

    El uso de cache evita leer y validar repetidamente las
    variables de entorno durante la ejecución de la API.

    La instancia permanece disponible durante el ciclo de vida
    del proceso actual.
    """

    return Settings()