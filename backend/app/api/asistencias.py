"""HuellApp · API de asistencia.

RESPONSABILIDADES
------------------------------------------------------------
- Exponer los endpoints de asistencia y coordinar consultas, validaciones y respuestas.

ESTADO ACTUAL
------------------------------------------------------------
- Las rutas y dependencias de este módulo definen el contrato HTTP.

SECURITY
------------------------------------------------------------
La autorización se valida en backend con la identidad autenticada.
No se deben confiar roles, actores ni permisos enviados por el navegador.
"""
from uuid import UUID
from datetime import date, datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.api.asignaciones import _normalizar_asistencia_db
from app.services.attendance_status import effective_attendance_state

router = APIRouter(prefix='/asistencias', tags=['Asistencia'])


def _read(query):
    """Materializa una consulta y convierte fallos de lectura en indisponibilidad temporal."""
    try:
        return query.execute().data or []
    except Exception as exc:
        raise HTTPException(503, 'No fue posible consultar la asistencia. Reintenta en unos momentos.') from exc


@router.get('')
def listar(actor=Depends(require_permission('VIEW_ASSIGNMENTS'))):
    """Permite la consulta de gestión solo a los roles administrativos previstos."""
    _require_management(actor)
    return _list_rows()


@router.get('/mias')
def listar_propias(actor=Depends(require_permission('REPORT_ATTENDANCE'))):
    """Restringe los resultados al identificador del usuario autenticado."""
    return _list_rows(str(actor.id))


def _require_management(actor):
    if actor.role_code not in ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'):
        raise HTTPException(403, 'No tienes acceso al panel de asistencia.')


def _list_query(owner=None, *, count=None):
    """Una definición de consulta para listado y exportación; owner siempre lo fija el servidor."""
    select = (
        'id,asignacion_id,usuario_id,estado:estados_participacion(codigo),'
        'usuario:usuarios!fk_asignacion_participantes_usuario(nombres,apellido_paterno,apellido_materno),'
        'asistencia:asistencias_asignacion(*),'
        'asignacion:asignaciones!inner(fecha,hora_inicio,hora_fin,activo,deleted_at,lugar,'
        'actividad:tipos_actividad(nombre),colegio:colegios(nombre))'
    )
    query = get_supabase_client().table('asignacion_participantes').select(
        select, **({'count': count} if count else {})
    ).eq('activo', True).is_('deleted_at', 'null').is_('asignacion.deleted_at', 'null')
    if owner is not None:
        query = query.eq('usuario_id', owner)
    return query


def _normalize_rows(rows):
    for row in rows:
        value = row.get('asistencia') or []
        if isinstance(value, dict):
            value = [value]
        row['asistencia'] = [_normalizar_asistencia_db(item) for item in value]
        for attendance in row['asistencia']:
            attendance['estado'] = effective_attendance_state(attendance['estado'], row.get('estado', {}).get('codigo'))
    return rows


def _list_rows(owner=None):
    """Conserva las reglas de estado efectivo y precisión usadas por la pantalla."""
    return _normalize_rows(_read(_list_query(owner)))


class AttendanceSnapshot(BaseModel):
    generated_at: datetime
    total: int
    items: list[dict]


def _export_snapshot(response, owner=None, *, fecha_desde=None, fecha_hasta=None, asignacion_id=None):
    response.headers['Cache-Control'] = 'no-store'
    if fecha_desde and fecha_hasta and fecha_desde > fecha_hasta:
        raise HTTPException(422, 'La fecha desde debe ser anterior o igual a la fecha hasta.')
    try:
        generated_at = datetime.now(timezone.utc)
        query = _list_query(owner, count='exact')
        if asignacion_id:
            query = query.eq('asignacion_id', str(asignacion_id))
        if fecha_desde:
            query = query.gte('asignacion.fecha', fecha_desde.isoformat())
        if fecha_hasta:
            query = query.lte('asignacion.fecha', fecha_hasta.isoformat())
        # Todas las relaciones son a uno (asistencia tiene FK UNIQUE).
        # No existe aquí una lista de participantes embebida que pueda recortarse.
        result = query.order('id').limit(10000).execute()
        rows, total = result.data, result.count
        if not isinstance(rows, list) or type(total) is not int or total < 0 or total < len(rows):
            raise ValueError('Missing or inconsistent exact count')
        if total > len(rows) or total > 10000:
            raise HTTPException(422, 'La consulta supera el límite de una sola respuesta de Supabase. Acota fechas o selecciona una instancia. No se generó un archivo parcial.')
        return AttendanceSnapshot(generated_at=generated_at, total=total, items=_normalize_rows(rows))
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, 'No fue posible comprobar la consulta completa de asistencia. Vuelve a intentarlo.') from exc


@router.get('/exportacion', response_model=AttendanceSnapshot)
def exportar(response: Response, fecha_desde: date | None = None, fecha_hasta: date | None = None,
             asignacion_id: UUID | None = None, actor=Depends(require_permission('VIEW_ASSIGNMENTS'))):
    _require_management(actor)
    return _export_snapshot(response, fecha_desde=fecha_desde, fecha_hasta=fecha_hasta, asignacion_id=asignacion_id)


@router.get('/mias/exportacion', response_model=AttendanceSnapshot)
def exportar_propias(response: Response, fecha_desde: date | None = None, fecha_hasta: date | None = None,
                     asignacion_id: UUID | None = None, actor=Depends(require_permission('REPORT_ATTENDANCE'))):
    # No se recibe usuario_id del navegador: conserva exactamente la consulta propia.
    return _export_snapshot(response, str(actor.id), fecha_desde=fecha_desde,
                            fecha_hasta=fecha_hasta, asignacion_id=asignacion_id)


@router.get('/propia/{asignacion_id}')
def propia(asignacion_id: UUID, actor=Depends(require_permission('REPORT_ATTENDANCE'))):
    """Consulta asistencia verificando que la participación pertenece al actor autenticado."""
    db = get_supabase_client()
    rows = _read(db.table('asignacion_participantes').select(
        'id,estado:estados_participacion(codigo),asignacion:asignaciones!inner(deleted_at)'
    ).eq('asignacion_id', str(asignacion_id)).eq('usuario_id', str(actor.id)).eq('activo', True).is_(
        'deleted_at', 'null').is_('asignacion.deleted_at', 'null'))
    if not rows:
        raise HTTPException(404, 'No tienes una participación disponible.')
    attendance = _read(db.table('asistencias_asignacion').select('*').eq(
        'asignacion_participante_id', rows[0]['id']))
    if not attendance:
        raise HTTPException(404, 'No hay registro de asistencia.')
    result = _normalizar_asistencia_db(attendance[0])
    result['estado'] = effective_attendance_state(result['estado'], (rows[0].get('estado') or {}).get('codigo'))
    return result
