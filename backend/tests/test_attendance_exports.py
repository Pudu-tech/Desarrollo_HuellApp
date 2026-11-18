"""Exportación de asistencia con PostgREST real y transporte HTTP simulado."""
import copy
from datetime import date
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch
from uuid import UUID, uuid4
import httpx
from postgrest import SyncPostgrestClient
from fastapi import HTTPException, Response
from app.api import asistencias


class AttendanceExportTests(TestCase):
    def setUp(self):
        self.actor = SimpleNamespace(id=uuid4(), role_code='DIRECTIVA')
        self.assignment = str(uuid4())
        self.other = str(uuid4())
        self.requests = []
        self.cap = 10000
        self.count_override = None
        self.no_count = False
        attendance = {'id': str(uuid4()), 'asignacion_participante_id': 'p',
                      'estado': 'PENDIENTE', 'precision_metros': 12.4,
                      'created_at': '2026-11-01T12:00:00Z', 'updated_at': '2026-11-01T12:00:00Z'}
        row = {'id': str(UUID(int=1)), 'asignacion_id': self.assignment,
               'usuario_id': str(self.actor.id), 'activo': True, 'deleted_at': None,
               'estado': {'codigo': 'ACEPTADA'}, 'usuario': {'nombres': 'Ana', 'apellido_paterno': 'Ñúñez'},
               'asistencia': [attendance], 'asignacion': {'fecha': '2026-11-01',
               'hora_inicio': '08:00:00', 'hora_fin': '09:00:00', 'activo': True, 'deleted_at': None,
               'lugar': 'Sala', 'actividad': {'nombre': 'Reflexión'}, 'colegio': None}}
        self.rows = [row, {**copy.deepcopy(row), 'id': str(UUID(int=2)), 'usuario_id': self.other,
                          'estado': {'codigo': 'RECHAZADA'},
                          'asignacion': {**row['asignacion'], 'fecha': '2026-11-30'}},
                     {**copy.deepcopy(row), 'id': str(UUID(int=3)),
                      'asignacion': {**row['asignacion'], 'fecha': '2026-12-01'}}]
        http = httpx.Client(transport=httpx.MockTransport(self.respond))
        self.addCleanup(http.close)
        self.db = SyncPostgrestClient('https://database.example.org', http_client=http)

    def respond(self, request):
        self.requests.append(request)
        p = request.url.params
        self.assertEqual(request.method, 'GET')
        self.assertEqual(request.url.path, '/asignacion_participantes')
        self.assertEqual(request.headers['Prefer'], 'count=exact')
        self.assertEqual(p['order'], 'id.asc')
        self.assertEqual(p['activo'].lower(), 'eq.true')
        self.assertEqual(p['deleted_at'], 'is.null')
        self.assertEqual(p['asignacion.deleted_at'], 'is.null')
        self.assertIn('asignaciones!inner(', p['select'])
        self.assertIn('usuarios!fk_asignacion_participantes_usuario', p['select'])
        rows = [copy.deepcopy(row) for row in self.rows if row['activo'] and row['deleted_at'] is None
                and row['asignacion']['deleted_at'] is None]
        for key in ('usuario_id', 'asignacion_id'):
            if p.get(key):
                rows = [row for row in rows if 'eq.' + row[key] == p[key]]
        for condition in p.get_list('asignacion.fecha'):
            op, value = condition.split('.', 1)
            rows = [row for row in rows if row['asignacion']['fecha'] >= value] if op == 'gte' else [row for row in rows if row['asignacion']['fecha'] <= value]
        total = len(rows) if self.count_override is None else self.count_override
        rows = rows[:min(self.cap, int(p['limit']))]
        total = '*' if self.no_count else total
        return httpx.Response(200, json=rows, headers={'Content-Range': f'0-{len(rows)-1}/{total}' if rows else f'*/{total}'})

    def call(self, personal=False, **filters):
        response = Response()
        with patch.object(asistencias, 'get_supabase_client', return_value=self.db):
            result = (asistencias.exportar_propias if personal else asistencias.exportar)(response, actor=self.actor, **filters)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(len(self.requests), 1)
        return result

    def test_november_includes_both_days_and_normalizes_existing_states(self):
        result = self.call(fecha_desde=date(2026, 11, 1), fecha_hasta=date(2026, 11, 30))
        self.assertEqual(result.total, 2)
        self.assertEqual(result.items[0]['asistencia'][0]['precision_gps'], 12.4)
        self.assertEqual(result.items[1]['asistencia'][0]['estado'], 'NO_REQUERIDA')
        self.assertIsNotNone(result.generated_at.tzinfo)

    def test_personal_query_filters_authenticated_actor_before_count(self):
        for role in ('MONITOR', 'DIRECTIVA', 'COORDINADOR'):
            self.requests.clear()
            self.actor.role_code = role
            result = self.call(personal=True)
            self.assertEqual(result.total, 2)
            self.assertTrue(all(row['usuario_id'] == str(self.actor.id) for row in result.items))
            self.assertEqual(self.requests[0].url.params['usuario_id'], 'eq.' + str(self.actor.id))

    def test_general_roles_keep_current_visibility(self):
        for role in ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR'):
            self.requests.clear()
            self.actor.role_code = role
            self.assertEqual(self.call().total, 3)
            self.assertNotIn('usuario_id', self.requests[0].url.params)

    def test_monitor_cannot_export_general_even_with_permission(self):
        self.actor.role_code = 'MONITOR'
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 403)
        self.assertEqual(self.requests, [])

    def test_general_and_personal_routes_require_existing_permissions(self):
        for path, permission in [('/asistencias/exportacion', 'VIEW_ASSIGNMENTS'), ('/asistencias/mias/exportacion', 'REPORT_ATTENDANCE')]:
            route = next(route for route in asistencias.router.routes if route.path == path)
            dependency = route.dependant.dependencies[0].call
            with self.assertRaises(HTTPException) as error:
                dependency(SimpleNamespace(effective_permissions=set()))
            self.assertEqual(error.exception.status_code, 403)
            actor = SimpleNamespace(effective_permissions={permission})
            self.assertIs(dependency(actor), actor)
            self.assertNotIn('usuario_id', [p.name for p in route.dependant.query_params])

    def test_assignment_context_applies_to_personal_query(self):
        self.rows[2]['asignacion_id'] = str(uuid4())
        result = self.call(personal=True, asignacion_id=UUID(self.assignment))
        self.assertEqual(result.total, 1)

    def test_truncated_response_fails_without_a_second_request(self):
        self.cap = 1
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 422)
        self.assertEqual(len(self.requests), 1)

    def test_personal_cap_does_not_fallback_to_general_query(self):
        self.cap = 1
        with self.assertRaises(HTTPException):
            self.call(personal=True)
        self.assertEqual(len(self.requests), 1)
        self.assertIn('usuario_id', self.requests[0].url.params)

    def test_inconsistent_count_and_missing_count_fail_closed(self):
        for count in (0, None):
            self.requests.clear()
            self.count_override = count
            self.no_count = count is None
            with self.assertRaises(HTTPException) as error:
                self.call()
            self.assertEqual(error.exception.status_code, 503)

    def test_empty_and_soft_deleted_rows(self):
        self.rows[0]['activo'] = False
        self.rows[1]['deleted_at'] = 'date'
        self.rows[2]['asignacion']['deleted_at'] = 'date'
        self.assertEqual(self.call().items, [])

    def test_invalid_dates_fail_before_any_query(self):
        with self.assertRaises(HTTPException) as error:
            self.call(fecha_desde=date(2026, 12, 1), fecha_hasta=date(2026, 11, 1))
        self.assertEqual(error.exception.status_code, 422)
        self.assertEqual(self.requests, [])

    def test_dict_and_empty_attendance_reuse_list_normalization(self):
        self.rows[0]['asistencia'] = self.rows[0]['asistencia'][0]
        self.rows[1]['asistencia'] = []
        result = self.call()
        self.assertEqual(result.items[0]['asistencia'][0]['estado'], 'PENDIENTE')
        self.assertEqual(result.items[1]['asistencia'], [])

    def test_reported_attendance_is_preserved_after_invitation_rejection(self):
        self.rows[1]['asistencia'][0]['estado'] = 'PRESENTE'
        self.assertEqual(self.call().items[1]['asistencia'][0]['estado'], 'PRESENTE')

    def test_database_error_is_sanitized(self):
        with patch.object(asistencias, 'get_supabase_client', side_effect=RuntimeError('secret')), self.assertRaises(HTTPException) as error:
            asistencias.exportar(Response(), actor=self.actor)
        self.assertEqual(error.exception.status_code, 503)
        self.assertNotIn('secret', error.exception.detail)
