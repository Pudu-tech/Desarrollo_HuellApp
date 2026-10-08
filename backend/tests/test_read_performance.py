import asyncio
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from app.api import colegios, users
from app.core import security
from app.services.participation_notifications import personal_summaries


class SecurityProjectionTests(unittest.TestCase):
    def test_assignment_summary_shares_authenticated_actor_and_permissions(self):
        from app.api import asignaciones, asignacion_catalogos
        actor = SimpleNamespace(role_code='DIRECTIVA', effective_permissions={'VIEW_ASSIGNMENTS', 'UPDATE_ASSIGNMENT'})
        with patch.object(asignaciones, 'listar_asignaciones', return_value=[]) as listing, \
             patch.object(asignacion_catalogos, 'listar_catalogos_asignaciones', return_value={'estados': []}) as catalogs:
            result = asignaciones.resumen_asignaciones(actor)
        listing.assert_called_once_with(current_user=actor)
        catalogs.assert_called_once_with(actor)
        self.assertEqual(result['permissions'], ['UPDATE_ASSIGNMENT', 'VIEW_ASSIGNMENTS'])
        paths = [route.path for route in asignaciones.router.routes]
        self.assertLess(paths.index('/asignaciones/resumen'), next(i for i, route in enumerate(asignaciones.router.routes)
                        if route.path == '/asignaciones/{asignacion_id}' and 'GET' in route.methods))

    def test_permissions_are_read_with_profile_and_revocation_is_immediate(self):
        db = Mock()
        user_id = uuid4()
        db.auth.get_user.return_value.user = SimpleNamespace(id=user_id)
        profile = {'id': str(user_id), 'email': 'person@example.org', 'nombres': 'Ana',
                   'apellido_paterno': 'Pérez', 'activo': True, 'deleted_at': None,
                   'roles': {'codigo': 'DIRECTIVA', 'rol_permiso': [
                       {'permisos': {'codigo': 'UPDATE_ASSIGNMENT', 'activo': True}},
                       {'permisos': {'codigo': 'DELETE_ASSIGNMENT', 'activo': False}}]}}
        db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value.data = profile
        credentials = HTTPAuthorizationCredentials(scheme='Bearer', credentials='test-token')
        with patch.object(security, 'get_supabase_client', return_value=db):
            actor = security.get_current_user(credentials)
            self.assertEqual(security.require_permission('UPDATE_ASSIGNMENT')(actor), actor)
            with self.assertRaises(HTTPException):
                security.require_permission('DELETE_ASSIGNMENT')(actor)
            self.assertNotIn('effective_permissions', actor.model_dump())
            profile['roles']['rol_permiso'] = []
            next_actor = security.get_current_user(credentials)
            with self.assertRaises(HTTPException):
                security.require_permission('UPDATE_ASSIGNMENT')(next_actor)
        self.assertEqual(db.table.call_count, 2)  # One profile query per request, no separate roles query.

    def test_personal_list_has_one_query_and_always_filters_owner(self):
        db = Mock()
        query = db.table.return_value.select.return_value
        query.eq.return_value = query
        query.is_.return_value = query
        query.execute.return_value.data = []
        self.assertEqual(personal_summaries(db, 'owner-id'), [])
        query.eq.assert_any_call('usuario_id', 'owner-id')
        query.is_.assert_any_call('asignacion.deleted_at', 'null')
        query.execute.assert_called_once()

    def test_deleted_assignment_never_appears_in_personal_panel(self):
        db = Mock()
        query = db.table.return_value.select.return_value
        query.eq.return_value = query
        query.is_.return_value = query
        query.execute.return_value.data = [{'asignacion': {'deleted_at': '2026-10-07T20:00:00Z'}}]
        self.assertEqual(personal_summaries(db, 'owner-id'), [])


class ReadConcurrencyTests(unittest.IsolatedAsyncioTestCase):
    async def test_two_database_reads_can_enter_at_the_same_time(self):
        barrier = threading.Barrier(2)

        class Query:
            def __getattr__(self, name):
                return lambda *args, **kwargs: self

            def execute(self):
                barrier.wait(timeout=2)
                return SimpleNamespace(data=[])

        app = FastAPI()
        for module in (colegios, users):
            app.include_router(module.router)
            route = next(r for r in module.router.routes if r.path == module.router.prefix and 'GET' in r.methods)
            app.dependency_overrides[route.dependant.dependencies[0].call] = lambda: SimpleNamespace(role_code='SUPERADMIN')
        with patch.object(colegios, 'get_supabase_client', return_value=Query()), patch.object(users, 'get_supabase_client', return_value=Query()):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url='http://test') as client:
                responses = await asyncio.gather(client.get('/colegios'), client.get('/users'))
        self.assertEqual([r.status_code for r in responses], [200, 200])
