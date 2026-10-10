"""Lecturas administrativas y propias de asistencia; escrituras usan RPC existentes."""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.api.asignaciones import _normalizar_asistencia_db

router = APIRouter(prefix='/asistencias', tags=['Asistencia'])


def _read(query):
    try:
        return query.execute().data or []
    except Exception as exc:
        raise HTTPException(503, 'No fue posible consultar la asistencia. Reintenta en unos momentos.') from exc


@router.get('')
def listar(actor=Depends(require_permission('VIEW_ASSIGNMENTS'))):
    if actor.role_code not in ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'):
        raise HTTPException(403, 'No tienes acceso al panel de asistencia.')
    return _list_rows()


@router.get('/mias')
def listar_propias(actor=Depends(require_permission('REPORT_ATTENDANCE'))):
    return _list_rows(str(actor.id))


def _list_rows(owner=None):
    query = get_supabase_client().table('asignacion_participantes').select(
        'id,asignacion_id,estado:estados_participacion(codigo),'
        'usuario:usuarios!fk_asignacion_participantes_usuario(nombres,apellido_paterno,apellido_materno),'
        'asistencia:asistencias_asignacion(*),'
        'asignacion:asignaciones!inner(fecha,hora_inicio,hora_fin,activo,deleted_at,lugar,'
        'actividad:tipos_actividad(nombre),colegio:colegios(nombre))'
    ).eq('activo', True).is_('deleted_at', 'null').is_('asignacion.deleted_at', 'null')
    if owner is not None:
        query = query.eq('usuario_id', owner)
    rows = _read(query)
    for row in rows:
        value = row.get('asistencia') or []
        if isinstance(value, dict):
            value = [value]
        row['asistencia'] = [_normalizar_asistencia_db(item) for item in value]
    return rows


@router.get('/propia/{asignacion_id}')
def propia(asignacion_id: UUID, actor=Depends(require_permission('REPORT_ATTENDANCE'))):
    db = get_supabase_client()
    rows = _read(db.table('asignacion_participantes').select(
        'id,asignacion:asignaciones!inner(deleted_at)'
    ).eq('asignacion_id', str(asignacion_id)).eq('usuario_id', str(actor.id)).eq('activo', True).is_(
        'deleted_at', 'null').is_('asignacion.deleted_at', 'null'))
    if not rows:
        raise HTTPException(404, 'No tienes una participación disponible.')
    attendance = _read(db.table('asistencias_asignacion').select('*').eq(
        'asignacion_participante_id', rows[0]['id']))
    if not attendance:
        raise HTTPException(404, 'No hay registro de asistencia.')
    return _normalizar_asistencia_db(attendance[0])
