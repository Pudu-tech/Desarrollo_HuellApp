"""Catálogos de apoyo para el formulario de colegios de HuellAPP.

Solo se exponen registros activos. Los endpoints están protegidos
por el mismo permiso de consulta que el mantenedor de colegios.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser


router = APIRouter(prefix="/catalogos", tags=["Catálogos"])


class RegionItem(BaseModel):
    """Contrato público de una región activa usada en selectores."""

    id: UUID
    codigo: str
    nombre: str


class ComunaItem(BaseModel):
    """Contrato público de una comuna, asociada por region_id."""

    id: UUID
    region_id: UUID
    nombre: str


class TipoDependenciaItem(BaseModel):
    """Contrato público de dependencia educativa activa."""

    id: UUID
    codigo: str
    nombre: str
    descripcion: str | None = None


@router.get("/regiones", response_model=list[RegionItem])
async def listar_regiones(
    _current_user: AuthenticatedUser = Depends(require_permission("VIEW_SCHOOLS")),
) -> list[RegionItem]:
    """Lista regiones activas ordenadas por nombre."""
    try:
        response = (
            get_supabase_client()
            .table("regiones")
            .select("id,codigo,nombre")
            .eq("activo", True)
            .order("nombre")
            .execute()
        )
        return [RegionItem.model_validate(item) for item in (response.data or [])]
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener las regiones.",
        ) from exc


@router.get("/comunas", response_model=list[ComunaItem])
async def listar_comunas(
    region_id: UUID = Query(..., description="UUID de la región seleccionada"),
    _current_user: AuthenticatedUser = Depends(require_permission("VIEW_SCHOOLS")),
) -> list[ComunaItem]:
    """Lista solo comunas activas de una región activa."""
    supabase = get_supabase_client()
    try:
        # No se listan comunas de una región inexistente o inactiva.
        region_response = (
            supabase.table("regiones")
            .select("id")
            .eq("id", str(region_id))
            .eq("activo", True)
            .maybe_single()
            .execute()
        )
        if not region_response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="La región seleccionada no existe o está inactiva.",
            )

        # La consulta restringe la relación para evitar selecciones inválidas.
        response = (
            supabase.table("comunas")
            .select("id,region_id,nombre")
            .eq("region_id", str(region_id))
            .eq("activo", True)
            .order("nombre")
            .execute()
        )
        return [ComunaItem.model_validate(item) for item in (response.data or [])]
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener las comunas.",
        ) from exc


@router.get("/tipos-dependencia", response_model=list[TipoDependenciaItem])
async def listar_tipos_dependencia(
    _current_user: AuthenticatedUser = Depends(require_permission("VIEW_SCHOOLS")),
) -> list[TipoDependenciaItem]:
    """Lista los tipos de dependencia activos."""
    try:
        response = (
            get_supabase_client()
            .table("tipos_dependencia")
            .select("id,codigo,nombre,descripcion")
            .eq("activo", True)
            .order("nombre")
            .execute()
        )
        return [
            TipoDependenciaItem.model_validate(item)
            for item in (response.data or [])
        ]
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No fue posible obtener los tipos de dependencia.",
        ) from exc
