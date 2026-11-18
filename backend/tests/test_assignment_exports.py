"""Constructor PostgREST real, transporte simulado y una única consulta de datos."""
import copy
from datetime import date
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch
from uuid import UUID, uuid4
import httpx
from postgrest import SyncPostgrestClient
from fastapi import Response, HTTPException
from app.api.assignment_exports import assignment_snapshot, router


class AssignmentExportTests(TestCase):
    def setUp(self):
        self.actor = SimpleNamespace(role_code='DIRECTIVA')
        self.requests = []
        self.cap, self.part_cap, self.omit_count = 10000, 10000, False
        self.school, self.kind, self.state = [str(uuid4()) for _ in range(3)]
        p1 = {'id': str(UUID(int=1)), 'activo': True, 'deleted_at': None,
              'usuario': {'nombres': 'Ana', 'apellido_paterno': 'Ñúñez'},
              'estado': {'codigo': 'ACEPTADA'}, 'asistencia': {'estado': 'PRESENTE'}}
        p2 = {**copy.deepcopy(p1), 'id': str(UUID(int=2)), 'usuario': {'nombres': 'Luis'},
              'estado': {'codigo': 'RECHAZADA'}, 'asistencia': [{'estado': 'PENDIENTE'}]}
        base = {'id': str(uuid4()), 'tipo_actividad_id': self.kind, 'colegio_id': self.school,
                'estado_id': self.state, 'fecha': '2026-11-01', 'hora_inicio': '08:00:00',
                'hora_fin': '08:45:00', 'activo': True, 'created_at': '2026-10-01T12:00:00Z',
                'updated_at': '2026-10-01T12:00:00Z', 'deleted_at': None,
                'tipo': {'codigo': 'ESPACIO_REFLEXION', 'nombre': 'Espacio de Reflexión'},
                'estado': {'codigo': 'PENDIENTE', 'nombre': 'Pendiente'},
                'colegio': {'nombre': 'Colegio de prueba', 'activo': True, 'deleted_at': None},
                'participaciones': [p1, p2]}
        self.rows = [base, {**copy.deepcopy(base), 'id': str(uuid4()), 'fecha': '2026-11-30',
                           'colegio_id': None, 'colegio': None, 'lugar': 'Casa Central', 'participaciones': []},
                     {**copy.deepcopy(base), 'id': str(uuid4()), 'fecha': '2026-12-01'}]
        http = httpx.Client(transport=httpx.MockTransport(self.respond))
        self.addCleanup(http.close)
        self.db = SyncPostgrestClient('https://database.example.org', http_client=http)

    def respond(self, request):
        self.requests.append(request)
        p = request.url.params
        self.assertEqual(request.method, 'GET')
        self.assertEqual(request.url.path, '/asignaciones')
        self.assertEqual(request.headers['Prefer'], 'count=exact')
        self.assertEqual(p['deleted_at'], 'is.null')
        self.assertEqual(p['order'], 'fecha.asc,hora_inicio.asc,id.asc')
        self.assertEqual(p['participaciones.order'], 'id.asc')
        self.assertEqual(p['participantes_control.order'], 'id.desc')
        for relation in ('participaciones', 'participantes_control'):
            self.assertEqual(p[f'{relation}.activo'].lower(), 'eq.true')
            self.assertEqual(p[f'{relation}.deleted_at'], 'is.null')
        rows = [copy.deepcopy(row) for row in self.rows if row.get('deleted_at') is None]
        for key in ('tipo_actividad_id', 'colegio_id', 'estado_id'):
            if p.get(key):
                rows = [row for row in rows if 'eq.' + str(row.get(key)) == p[key]]
        if p.get('fecha'):
            for value in p.get_list('fecha'):
                op, day = value.split('.', 1)
                rows = [row for row in rows if row['fecha'] >= day] if op == 'gte' else [row for row in rows if row['fecha'] <= day]
        total = len(rows)
        rows = rows[:min(self.cap, int(p['limit']))]
        for row in rows:
            parts = sorted([part for part in row['participaciones'] if part['activo'] and not part.get('deleted_at')], key=lambda part: part['id'])
            row['participaciones'] = parts[:self.part_cap]
            row['participantes_control'] = [{'id': part['id']} for part in list(reversed(parts))[:self.part_cap]]
        count = '*' if self.omit_count else total
        return httpx.Response(200, json=rows, headers={'Content-Range': f'0-{len(rows)-1}/{count}' if rows else f'*/{count}'})

    def call(self, **filters):
        response = Response()
        with patch('app.api.assignment_exports.get_supabase_client', return_value=self.db):
            result = assignment_snapshot(response, actor=self.actor, **filters)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(len(self.requests), 1)
        return result

    def test_november_includes_both_boundaries_and_readable_relations(self):
        result = self.call(fecha_desde=date(2026, 11, 1), fecha_hasta=date(2026, 11, 30))
        self.assertEqual(result.total, 2)
        self.assertEqual(result.items[0].asignados_a, ['Ana Ñúñez', 'Luis'])
        self.assertEqual(result.items[0].asistencia_resumen, {'PRESENTE': 1, 'NO_REQUERIDA': 1})
        self.assertEqual(result.catalogos['colegios'][0]['nombre'], 'Colegio de prueba')
        self.assertEqual(result.items[1].lugar, 'Casa Central')

    def test_root_filters_are_sent_before_count(self):
        self.assertEqual(self.call(colegio_id=UUID(self.school), tipo_actividad_id=UUID(self.kind), estado_id=UUID(self.state)).total, 2)

    def test_coordinator_and_superadmin_use_current_general_visibility(self):
        for role in ('COORDINADOR', 'SUPERADMIN'):
            self.requests.clear()
            self.actor.role_code = role
            self.assertEqual(self.call().total, 3)

    def test_monitor_is_rejected_before_query(self):
        self.actor.role_code = 'MONITOR'
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 403)
        self.assertEqual(self.requests, [])

    def test_invalid_dates_do_not_read_database(self):
        with self.assertRaises(HTTPException) as error:
            self.call(fecha_desde=date(2026, 12, 1), fecha_hasta=date(2026, 11, 1))
        self.assertEqual(error.exception.status_code, 422)
        self.assertEqual(self.requests, [])

    def test_truncated_root_is_rejected_without_another_page(self):
        self.cap = 1
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 422)
        self.assertEqual(len(self.requests), 1)

    def test_truncated_participants_are_also_rejected(self):
        self.part_cap = 1
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 422)
        self.assertIn('participantes', error.exception.detail)
        self.assertEqual(len(self.requests), 1)

    def test_single_rejection_and_inactive_participants_keep_existing_rules(self):
        self.rows = self.rows[:1]
        self.rows[0]['participaciones'][0]['activo'] = False
        result = self.call()
        self.assertTrue(result.items[0].por_reasignar)
        self.assertEqual(result.items[0].asignados_a, ['Luis'])

    def test_deleted_rows_are_excluded_and_empty_result_is_valid(self):
        for row in self.rows:
            row['deleted_at'] = '2026-11-15'
        self.assertEqual(self.call().total, 0)

    def test_missing_count_is_not_assumed_complete(self):
        self.omit_count = True
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 503)

    def test_missing_relation_control_is_rejected(self):
        from app.api.assignment_exports import _participants_complete
        with self.assertRaises(ValueError):
            _participants_complete({'participaciones': []})

    def test_existing_permission_dependency_is_required(self):
        dependency = router.routes[0].dependant.dependencies[0].call
        with self.assertRaises(HTTPException):
            dependency(SimpleNamespace(effective_permissions=set()))

    def test_database_failure_does_not_expose_details(self):
        with patch('app.api.assignment_exports.get_supabase_client', side_effect=RuntimeError('secret')), self.assertRaises(HTTPException) as error:
            assignment_snapshot(Response(), actor=self.actor)
        self.assertEqual(error.exception.status_code, 503)
        self.assertNotIn('secret', error.exception.detail)
