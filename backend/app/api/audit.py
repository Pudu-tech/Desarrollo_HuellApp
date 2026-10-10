"""Consulta paginada de auditoría, protegida por VIEW_AUDIT_LOGS."""
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.audit import AuditLogItem
from app.schemas.auth import AuthenticatedUser

router = APIRouter(prefix='/audit', tags=['Audit'])

def person(row):
    return ' '.join(str(row.get(k) or '') for k in ('nombres', 'apellido_paterno', 'apellido_materno')).strip()

@router.get('/options')
def options(current_user: AuthenticatedUser = Depends(require_permission('VIEW_AUDIT_LOGS'))):
    db = get_supabase_client()
    try:
        users = db.table('usuarios').select('id,nombres,apellido_paterno,apellido_materno').order('nombres').execute().data or []
        roles = db.table('roles').select('id,codigo').execute().data or []
        return {'users': [{'id': r['id'], 'name': person(r)} for r in users], 'roles': roles}
    except Exception as exc:
        raise HTTPException(503, 'No fue posible cargar los filtros de auditoría.') from exc

@router.get('', response_model=list[AuditLogItem])
def list_audit_logs(limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0),
                    action: str | None = None, entity_type: str | None = None,
                    actor_user_id: UUID | None = None, actor_role_id: UUID | None = None,
                    desde: date | None = None, hasta: date | None = None,
                    search: str | None = Query(None, max_length=150), asignacion: UUID | None = None,
                    current_user: AuthenticatedUser = Depends(require_permission('VIEW_AUDIT_LOGS'))):
    if desde and hasta and desde > hasta:
        raise HTTPException(422, 'La fecha inicial debe ser anterior o igual a la final.')
    db = get_supabase_client()
    try:
        query = db.table('audit_logs').select('*')
        for column, value in (('action', action), ('entity_type', entity_type), ('actor_user_id', actor_user_id), ('actor_role_id', actor_role_id)):
            if value: query = query.eq(column, str(value).strip().upper() if column in ('action','entity_type') else str(value))
        zone = ZoneInfo('America/Santiago')
        if desde: query = query.gte('created_at', datetime.combine(desde, time.min, zone).isoformat())
        if hasta: query = query.lt('created_at', datetime.combine(hasta + timedelta(days=1), time.min, zone).isoformat())
        if search and search.strip(): query = query.ilike('description', '%' + search.strip().replace('%', '').replace('_', '') + '%')
        if asignacion:
            # Incluye las respuestas y asistencias, incluso de participantes retirados.
            parts = db.table('asignacion_participantes').select('id').eq('asignacion_id', str(asignacion)).execute().data or []
            ids = [str(asignacion)] + [r['id'] for r in parts]
            if parts:
                attendance = db.table('asistencias_asignacion').select('id').in_('asignacion_participante_id', [r['id'] for r in parts]).execute().data or []
                ids.extend(r['id'] for r in attendance)
            query = query.in_('entity_id', ids)
        rows = query.order('created_at', desc=True).order('id', desc=True).range(offset, offset+limit-1).execute().data or []
        actor_ids = list({r['actor_user_id'] for r in rows if r.get('actor_user_id')})
        role_ids = list({r['actor_role_id'] for r in rows if r.get('actor_role_id')})
        users = {r['id']: person(r) for r in (db.table('usuarios').select('id,nombres,apellido_paterno,apellido_materno').in_('id',actor_ids).execute().data or [])} if actor_ids else {}
        roles = {r['id']:r['codigo'] for r in (db.table('roles').select('id,codigo').in_('id',role_ids).execute().data or [])} if role_ids else {}
        # Recupera nombres en lotes, sin una consulta por evento.
        names = {}
        for types, table, columns in ((('USER',), 'usuarios', 'id,nombres,apellido_paterno,apellido_materno'), (('SCHOOL',), 'colegios', 'id,nombre'), (('ROOM',), 'salas', 'id,nombre'), (('ASSIGNMENT',), 'asignaciones', 'id,fecha,lugar')):
            ids = list({r['entity_id'] for r in rows if r['entity_type'] in types and r.get('entity_id')})
            if ids:
                for entity in db.table(table).select(columns).in_('id',ids).execute().data or []:
                    names[entity['id']] = person(entity) if table == 'usuarios' else entity.get('nombre') or f"Actividad del {entity.get('fecha')} · {entity.get('lugar') or 'Colegio'}"
        for row in rows:
            row['actor_name'] = users.get(row.get('actor_user_id'), 'Sistema' if not row.get('actor_user_id') else 'Usuario no disponible')
            row['actor_role'] = roles.get(row.get('actor_role_id'))
            values = row.get('new_values') or row.get('old_values') or {}
            row['entity_name'] = names.get(row.get('entity_id')) or values.get('nombre') or values.get('nombre_mostrado') or row.get('description')
        return [AuditLogItem.model_validate(r) for r in rows]
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, 'No fue posible obtener los registros de auditoría. Reintenta.') from exc
