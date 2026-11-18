"""Consulta PostgREST real con transporte HTTP simulado, sin Supabase real."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4
import httpx
from postgrest import SyncPostgrestClient
from fastapi import HTTPException, Response
from app.api.user_exports import user_snapshot, router


class ExportQueryTests(unittest.TestCase):
    def setUp(self):
        self.actor = SimpleNamespace(id=str(uuid4()), role_code='DIRECTIVA')
        self.requests = []
        self.rows = []
        for role in ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR', 'MONITOR'):
            self.rows.append({'id': str(uuid4()), 'rut': '12345678-5', 'nombres': role,
                             'apellido_paterno': 'Prueba', 'apellido_materno': '',
                             'email': role.lower() + '@example.org', 'telefono': None,
                             'activo': role != 'MONITOR', 'deleted_at': None,
                             'roles': {'codigo': role, 'nombre': role}})
        self.rows.append(dict(self.rows[-1], id=str(uuid4()), deleted_at='2026-11-15'))
        self.cap = 10000
        self.omit_count = False
        http = httpx.Client(transport=httpx.MockTransport(self.respond))
        self.addCleanup(http.close)
        self.db = SyncPostgrestClient('https://database.example.org', http_client=http)

    def respond(self, request):
        self.requests.append(request)
        self.assertEqual(request.method, 'GET')
        self.assertEqual(request.url.path, '/usuarios')
        self.assertEqual(request.headers['Prefer'], 'count=exact')
        self.assertIn('roles!inner(', request.url.params['select'])
        self.assertEqual(request.url.params['deleted_at'], 'is.null')
        self.assertEqual(request.url.params['limit'], '10000')
        self.assertEqual(request.url.params['order'], 'apellido_paterno.asc,nombres.asc,id.asc')
        rows = [row for row in self.rows if row['deleted_at'] is None]
        if request.url.params.get('roles.codigo') == 'neq.SUPERADMIN':
            rows = [row for row in rows if row['roles']['codigo'] != 'SUPERADMIN']
        total = len(rows)
        rows = rows[:min(self.cap, int(request.url.params['limit']))]
        count = '*' if self.omit_count else str(total)
        span = f'0-{len(rows)-1}' if rows else '*'
        return httpx.Response(200, headers={'Content-Range': f'{span}/{count}'}, json=rows)

    def call(self):
        response = Response()
        with patch('app.api.user_exports.get_supabase_client', return_value=self.db):
            result = user_snapshot(response, self.actor)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(len(self.requests), 1)
        self.assertIsNotNone(result.generated_at.tzinfo)
        return result

    def test_directiva_one_read_excludes_superadmin_and_deleted(self):
        result = self.call()
        self.assertEqual(result.total, 3)
        self.assertNotIn('SUPERADMIN', {row.roles.codigo for row in result.items})
        self.assertTrue(any(not row.activo for row in result.items))

    def test_superadmin_keeps_all_roles(self):
        self.actor.role_code = 'SUPERADMIN'
        self.assertEqual(self.call().total, 4)
        self.assertNotIn('roles.codigo', self.requests[0].url.params)

    def test_empty_result_is_complete(self):
        self.rows = []
        self.assertEqual(self.call().total, 0)

    def test_server_cap_rejected_without_fetching_another_page(self):
        self.cap = 1
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 422)
        self.assertIn('No se generó un archivo parcial', error.exception.detail)
        self.assertEqual(len(self.requests), 1)

    def test_exact_server_cap_is_accepted_when_count_matches(self):
        self.cap = 3
        self.assertEqual(self.call().total, 3)

    def test_missing_exact_count_is_rejected(self):
        self.omit_count = True
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 503)
        self.assertEqual(len(self.requests), 1)

    def test_more_than_1000_is_supported_when_server_allows_it(self):
        self.rows = [dict(self.rows[-2], id=str(uuid4())) for _ in range(1001)]
        self.assertEqual(self.call().total, 1001)

    def test_application_cap_does_not_silently_truncate(self):
        self.rows = [dict(self.rows[-2], id=str(uuid4())) for _ in range(10001)]
        with self.assertRaises(HTTPException) as error:
            self.call()
        self.assertEqual(error.exception.status_code, 422)
        self.assertEqual(len(self.requests), 1)

    def test_database_errors_are_sanitized(self):
        with patch('app.api.user_exports.get_supabase_client', side_effect=RuntimeError('private configuration')), self.assertRaises(HTTPException) as error:
            user_snapshot(Response(), self.actor)
        self.assertEqual(error.exception.status_code, 503)
        self.assertNotIn('private', error.exception.detail)

    def test_other_roles_rejected_before_query(self):
        for role in ('COORDINADOR', 'MONITOR'):
            self.actor.role_code = role
            with patch('app.api.user_exports.get_supabase_client') as db, self.assertRaises(HTTPException) as error:
                user_snapshot(Response(), self.actor)
            self.assertEqual(error.exception.status_code, 403)
            db.assert_not_called()

    def test_route_uses_existing_permission_dependency(self):
        dependency = router.routes[0].dependant.dependencies[0].call
        with self.assertRaises(HTTPException):
            dependency(SimpleNamespace(effective_permissions=set()))

    def test_invalid_or_inconsistent_count_is_rejected(self):
        db = Mock()
        query = db.table.return_value.select.return_value
        for method in ('is_', 'order', 'limit', 'neq'):
            getattr(query, method).return_value = query
        for count in (-1, True, 0):
            query.execute.return_value = SimpleNamespace(data=self.rows[:1], count=count)
            with patch('app.api.user_exports.get_supabase_client', return_value=db), self.assertRaises(HTTPException) as error:
                user_snapshot(Response(), self.actor)
            self.assertEqual(error.exception.status_code, 503)
