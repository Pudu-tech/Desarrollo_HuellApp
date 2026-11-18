"""Exportación de Instancias: una lectura completa o un error, sin migraciones."""
from datetime import date, datetime, timezone
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from app.core.security import require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.schemas.asignaciones import AsignacionListItem
from app.api.asignaciones import ASIGNACION_SELECT, _asignados_a, _attendance_counts, _por_reasignar

router = APIRouter(prefix='/exports', tags=['Exportación'])


class AssignmentSnapshot(BaseModel):
    generated_at: datetime
    total: int
    items: list[AsignacionListItem]
    catalogos: dict[str, list[dict]]


def _participants_complete(row):
    # Dos órdenes opuestos en la MISMA consulta detectan también recortes de
    # relaciones embebidas: primeros/últimos IDs solo coinciden si llegaron todos.
    parts, control = row.get('participaciones'), row.get('participantes_control')
    if not isinstance(parts, list) or not isinstance(control, list):
        raise ValueError('Missing relation control')
    ids = [part.get('id') for part in parts]
    check = [part.get('id') for part in control]
    if any(not key for key in ids + check) or len(set(ids)) != len(ids) or len(set(check)) != len(check):
        raise ValueError('Invalid participant identifiers')
    if set(ids) != set(check):
        raise HTTPException(422, 'Supabase devolvió participantes incompletos. No se generó un archivo parcial.')
    return parts


@router.get('/assignments', response_model=AssignmentSnapshot)
def assignment_snapshot(response: Response, tipo_actividad_id: UUID | None = None,
                        colegio_id: UUID | None = None, estado_id: UUID | None = None,
                        fecha_desde: date | None = None, fecha_hasta: date | None = None,
                        actor: AuthenticatedUser = Depends(require_permission('VIEW_ASSIGNMENTS'))):
    response.headers['Cache-Control'] = 'no-store'
    # Decisión explícita de Matías: Coordinación conserva la visibilidad general
    # actual. El ámbito por colegio de #61 continúa como trabajo independiente.
    if actor.role_code not in ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'):
        raise HTTPException(403, 'No tienes permisos para exportar el listado general de instancias.')
    if fecha_desde and fecha_hasta and fecha_desde > fecha_hasta:
        raise HTTPException(422, 'La fecha desde debe ser anterior o igual a la fecha hasta.')
    try:
        generated_at = datetime.now(timezone.utc)
        select = ASIGNACION_SELECT + (
            ',tipo:tipos_actividad!tipo_actividad_id(codigo,nombre)'
            ',estado:estados_asignacion!estado_id(codigo,nombre)'
            ',colegio:colegios!colegio_id(nombre,activo,deleted_at)'
            ',participaciones:asignacion_participantes(id,activo,deleted_at,'
            'usuario:usuarios!usuario_id(nombres,apellido_paterno,apellido_materno),'
            'asistencia:asistencias_asignacion(estado),estado:estados_participacion!estado_participacion_id(codigo))'
            ',participantes_control:asignacion_participantes(id)'
        )
        query = get_supabase_client().table('asignaciones').select(select, count='exact').is_('deleted_at', 'null')
        for column, value in [('tipo_actividad_id', tipo_actividad_id), ('colegio_id', colegio_id), ('estado_id', estado_id)]:
            if value is not None:
                query = query.eq(column, str(value))
        if fecha_desde:
            query = query.gte('fecha', fecha_desde.isoformat())
        if fecha_hasta:
            query = query.lte('fecha', fecha_hasta.isoformat())
        for relation in ('participaciones', 'participantes_control'):
            query = query.eq(f'{relation}.activo', True).is_(f'{relation}.deleted_at', 'null')
        result = (query.order('fecha').order('hora_inicio').order('id')
                  .order('id', foreign_table='participaciones')
                  .order('id', desc=True, foreign_table='participantes_control').limit(10000).execute())
        rows, total = result.data, result.count
        if not isinstance(rows, list) or type(total) is not int or total < 0 or total < len(rows):
            raise ValueError('Missing or inconsistent exact count')
        if total > len(rows) or total > 10000:
            raise HTTPException(422, 'La consulta supera el límite de una sola respuesta de Supabase. Acota fechas, colegio o tipo de actividad. No se generó un archivo parcial.')
        items = []
        catalogs = {'tipos_actividad': {}, 'estados': {}, 'colegios': {}}
        for row in rows:
            parts = _participants_complete(row)
            items.append(AsignacionListItem.model_validate({**row, 'por_reasignar': _por_reasignar(row, parts),
                         'asignados_a': _asignados_a(parts), 'asistencia_resumen': _attendance_counts(parts)}))
            for group, source, key in [('tipos_actividad', 'tipo', 'tipo_actividad_id'), ('estados', 'estado', 'estado_id'), ('colegios', 'colegio', 'colegio_id')]:
                if row.get(source) and row.get(key):
                    catalogs[group][row[key]] = {'id': row[key], **row[source]}
        return AssignmentSnapshot(generated_at=generated_at, total=total, items=items,
                                  catalogos={key: list(values.values()) for key, values in catalogs.items()})
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, 'No fue posible comprobar la consulta completa de instancias. Vuelve a intentarlo.') from exc
