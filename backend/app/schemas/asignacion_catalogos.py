"""HuellAPP · Contratos mínimos de consulta para el formulario de Asignaciones.

Las opciones proceden de tablas existentes. No reciben actor ni estado inicial.
Las proyecciones de usuarios solo identifican participantes elegibles.
"""
from uuid import UUID
from pydantic import BaseModel


class OpcionNombre(BaseModel):
    """Identificador y nombre de un recurso existente."""
    id: UUID
    nombre: str


class OpcionCodigo(OpcionNombre):
    """Catálogo con código estable de negocio."""
    codigo: str


class ParticipanteOpcion(BaseModel):
    """Proyección pública para seleccionar participantes, sin datos de cuenta."""
    id: UUID
    nombres: str
    apellido_paterno: str
    apellido_materno: str | None = None
    role_code: str


class CursoOpcion(BaseModel):
    """Curso disponible del colegio elegido; permite filtrar ramos por nivel."""
    id: UUID
    nombre_mostrado: str
    nivel_curso_id: UUID
    anio: int


class RamoOpcion(OpcionNombre):
    nivel_curso_id: UUID | None = None
    nivel_ids: list[UUID]


class ContactoOpcion(OpcionNombre):
    apellido_paterno: str | None = None
    apellido_materno: str | None = None
    cargo: str | None = None


class CatalogosAsignacion(BaseModel):
    """Nombres de catálogo e históricos necesarios para el listado de gestión."""
    tipos_actividad: list[OpcionCodigo]
    estados: list[OpcionCodigo]
    colegios: list[OpcionNombre]


class OpcionesCreacionAsignacion(BaseModel):
    """Solo actividades autorizadas y recursos activos para nuevas asignaciones."""
    tipos_actividad: list[OpcionCodigo]
    colegios: list[OpcionNombre]
    participantes: list[ParticipanteOpcion]
    tipos_participacion: list[OpcionCodigo]
    ramos: list[RamoOpcion]


class OpcionesColegioAsignacion(BaseModel):
    cursos: list[CursoOpcion]
    salas: list[OpcionNombre]
    contactos: list[ContactoOpcion]


class OpcionesEspaciosAsignacion(BaseModel):
    reflexion: list[OpcionNombre]
    encuentro: list[OpcionNombre]
