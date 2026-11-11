"""Visibilidad del mantenedor por rol, usando HTTP y el constructor real de PostgREST.

El transporte simula únicamente la base de datos; no usa credenciales ni servicios
remotos. Verifica filtros enviados, contratos, permisos y acceso por UUID/foto.
"""
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

import httpx
from fastapi import FastAPI
from fastapi.testclient import TestClient
from postgrest import SyncPostgrestClient

from app.api import users
from app.core.security import get_current_user


class UserVisibilityTests(unittest.TestCase):
    """Comprueba que la API nunca entregue cuentas Superadmin a Directiva."""

    def setUp(self):
        self.rows = []
        for role in ('SUPERADMIN', 'DIRECTIVA', 'COORDINADOR', 'MONITOR'):
            self.rows.append({'id': str(uuid4()), 'rut': '12345678-5', 'nombres': role,
                              'apellido_paterno': 'Prueba', 'apellido_materno': 'Local',
                              'email': role.lower() + '@example.org', 'activo': role != 'MONITOR',
                              'deleted_at': None, 'roles': {'codigo': role, 'nombre': role},
                              'foto_perfil_path': 'test/photo.png'})
        self.deleted = dict(self.rows[3], id=str(uuid4()), deleted_at='2026-11-10')
        self.rows.append(self.deleted)
        self.requests = []
        transport = httpx.MockTransport(self.database_response)
        http = httpx.Client(transport=transport)
        self.addCleanup(http.close)
        db = SyncPostgrestClient('https://database.example.org', http_client=http)
        self.db_patch = patch.object(users, 'get_supabase_client', return_value=db)
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)
        self.actor = SimpleNamespace(role_code='DIRECTIVA', effective_permissions={'VIEW_USERS'})
        app = FastAPI()
        app.include_router(users.router)
        app.dependency_overrides[get_current_user] = lambda: self.actor
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def database_response(self, request):
        """Simula la relación: un filtro sin !inner no excluye la fila principal."""
        self.requests.append(request)
        params = request.url.params
        rows = self.rows[:]
        if params.get('deleted_at') == 'is.null':
            rows = [r for r in rows if r['deleted_at'] is None]
        if params.get('id'):
            rows = [r for r in rows if 'eq.' + r['id'] == params['id']]
        if params.get('roles.codigo') == 'neq.SUPERADMIN' and 'roles!inner(' in params.get('select', ''):
            rows = [r for r in rows if r['roles']['codigo'] != 'SUPERADMIN']
        return httpx.Response(200, json=rows)

    def test_superadmin_lists_all_roles_including_inactive_but_not_deleted(self):
        self.actor.role_code = 'SUPERADMIN'
        response = self.client.get('/users')
        self.assertEqual(response.status_code, 200)
        self.assertEqual({r['roles']['codigo'] for r in response.json()},
                         {'SUPERADMIN', 'DIRECTIVA', 'COORDINADOR', 'MONITOR'})
        self.assertNotIn('roles.codigo', self.requests[-1].url.params)
        self.assertNotIn(self.deleted['id'], [r['id'] for r in response.json()])
        self.assertTrue(any(not r['activo'] for r in response.json()))

    def test_directiva_lists_other_roles_and_cannot_override_filter(self):
        response = self.client.get('/users?role_code=SUPERADMIN')
        self.assertEqual(response.status_code, 200)
        self.assertEqual({r['roles']['codigo'] for r in response.json()},
                         {'DIRECTIVA', 'COORDINADOR', 'MONITOR'})
        self.assertEqual(self.requests[-1].url.params['roles.codigo'], 'neq.SUPERADMIN')

    def test_directiva_cannot_read_superadmin_detail_or_sign_photo(self):
        with patch('app.api.profile.present') as present:
            for suffix in ('', '/photo'):
                response = self.client.get('/users/' + self.rows[0]['id'] + suffix)
                self.assertEqual(response.status_code, 404)
                self.assertEqual(response.json(), {'detail': 'Usuario no encontrado.'})
            present.assert_not_called()

    def test_superadmin_can_read_superadmin_and_directiva_can_read_monitor(self):
        for actor_role, row in (('SUPERADMIN', self.rows[0]), ('DIRECTIVA', self.rows[3])):
            self.actor.role_code = actor_role
            with patch('app.api.profile.present', return_value={'foto_url': 'https://example.org/photo'}):
                detail = self.client.get('/users/' + row['id'])
                self.assertEqual(detail.status_code, 200)
                self.assertEqual(detail.json()['id'], row['id'])
                photo = self.client.get('/users/' + row['id'] + '/photo')
                self.assertEqual(photo.status_code, 200)
                self.assertEqual(photo.json()['foto_url'], 'https://example.org/photo')

    def test_view_users_permission_still_required(self):
        self.actor.effective_permissions = set()
        for path in ('/users', '/users/' + self.rows[0]['id'], '/users/' + self.rows[0]['id'] + '/photo'):
            self.assertEqual(self.client.get(path).status_code, 403)
        self.assertEqual(self.requests, [])


if __name__ == '__main__':
    unittest.main()
