"""Lectura consistente para exportar exclusivamente las columnas de Usuarios."""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.users import UserListItem
from app.api.users import _visible_users_query

router = APIRouter(prefix='/exports', tags=['Exportación'])


class UserSnapshot(BaseModel):
    generated_at: datetime
    total: int
    items: list[UserListItem]


@router.get('/users', response_model=UserSnapshot)
def user_snapshot(response: Response, actor: AuthenticatedUser = Depends(require_permission('VIEW_USERS'))):
    response.headers['Cache-Control'] = 'no-store'
    if actor.role_code not in ('SUPERADMIN', 'DIRECTIVA'):
        raise HTTPException(403, 'No tienes permisos para exportar usuarios.')
    try:
        generated_at = datetime.now(timezone.utc)
        query = (
            get_supabase_client().table('usuarios')
            .select('id,rut,nombres,apellido_paterno,apellido_materno,email,telefono,activo,roles!inner(codigo,nombre)', count='exact')
            .is_('deleted_at', 'null')
            .order('apellido_paterno').order('nombres').order('id')
            .limit(10000)
        )
        # Conteo y filas en la misma petición; no hay HEAD previo, RPC ni paginación.
        result = _visible_users_query(query, actor).execute()
        rows, total = result.data, result.count
        if not isinstance(rows, list) or type(total) is not int or total < 0:
            raise ValueError('Missing exact count')
        if total > len(rows) or total > 10000:
            raise HTTPException(422, 'La consulta supera el límite de una sola respuesta de Supabase. No se generó un archivo parcial.')
        if total != len(rows):
            raise ValueError('Incomplete snapshot')
        return UserSnapshot(generated_at=generated_at, total=total, items=rows)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, 'No fue posible comprobar la consulta completa para exportar. Vuelve a intentarlo.') from exc
