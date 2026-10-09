import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4
from fastapi import HTTPException
from starlette.requests import Request
from app.api import asignaciones as api


class AssignmentDeletionTests(unittest.IsolatedAsyncioTestCase):
    async def test_administrators_call_atomic_rpc_with_audit_context(self):
        for role in ('SUPERADMIN', 'DIRECTIVA'):
            client = Mock()
            client.rpc.return_value.execute.return_value.data = {'ok': True}
            actor, assignment, request_id = uuid4(), uuid4(), uuid4()
            request = Request({'type': 'http', 'headers': [(b'user-agent', b'test')],
                               'client': ('127.0.0.1', 123), 'state': {'request_id': request_id}})
            with patch.object(api, 'get_supabase_client', return_value=client):
                self.assertIsNone(api.eliminar_asignacion(request, assignment, SimpleNamespace(id=actor, role_code=role)))
            name, payload = client.rpc.call_args.args
            self.assertEqual(name, 'eliminar_asignacion_atomica')
            self.assertEqual(payload['p_asignacion_id'], str(assignment))
            self.assertEqual(payload['p_actor_user_id'], str(actor))
            self.assertEqual(payload['p_request_id'], str(request_id))
            client.table.assert_not_called()

    async def test_non_admin_never_calls_rpc_even_if_given_permission(self):
        for role in ('COORDINADOR', 'MONITOR'):
            with patch.object(api, 'get_supabase_client') as client:
                with self.assertRaises(HTTPException) as error:
                    api.eliminar_asignacion(Request({'type': 'http', 'headers': []}), uuid4(), SimpleNamespace(role_code=role))
                self.assertEqual(error.exception.status_code, 403)
                client.assert_not_called()

    async def test_rpc_error_codes(self):
        for code, expected in [('NOT_FOUND', 404), ('FORBIDDEN', 403), ('ACTOR_NOT_FOUND', 403)]:
            client = Mock()
            client.rpc.return_value.execute.return_value.data = {'ok': False, 'error_code': code}
            with patch.object(api, 'get_supabase_client', return_value=client):
                with self.assertRaises(HTTPException) as error:
                    api.eliminar_asignacion(Request({'type': 'http', 'headers': []}), uuid4(), SimpleNamespace(id=uuid4(), role_code='DIRECTIVA'))
                self.assertEqual(error.exception.status_code, expected)
