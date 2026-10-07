"""HuellAPP · Traducción de conflictos de integridad escolar de PostgreSQL.

Los triggers son la última protección frente a carreras con eliminación lógica.
Se reconocen códigos estables; nunca se expone el detalle interno de SQL.
"""
from fastapi import HTTPException


def raise_school_resource_conflict(error: Exception) -> None:
    """Convierte las validaciones del trigger en conflictos HTTP comprensibles."""
    message = str(error)
    if "RESOURCE_COURSE_LEVEL_IN_USE" in message:
        raise HTTPException(409, "El curso tiene asignaciones académicas y conserva su nivel histórico. Crea otro curso para un grado diferente.") from error
    if "RESOURCE_SCHOOL_IMMUTABLE" in message:
        raise HTTPException(409, "El recurso pertenece a este colegio y no puede trasladarse a otro.") from error
    if "SCHOOL_RESOURCE_UNAVAILABLE" in message:
        raise HTTPException(409, "El colegio está eliminado o inactivo; no permite esta operación sobre sus recursos.") from error
