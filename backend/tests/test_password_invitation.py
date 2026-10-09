import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4
from starlette.requests import Request
from fastapi import HTTPException
from app.api import users


class PasswordInvitationTests(unittest.TestCase):
    def test_administrator_requests_reset_and_audits_without_returning_token(self):
        for role in ('SUPERADMIN', 'DIRECTIVA'):
            db = Mock()
            query = db.table.return_value
            query.select.return_value = query
            query.eq.return_value = query
            query.is_.return_value = query
            query.single.return_value = query
            query.insert.return_value = query
            query.execute.side_effect = [SimpleNamespace(data=[{'id': str(uuid4()), 'email': 'monitor@example.org', 'activo': True, 'roles': {'codigo': 'MONITOR'}}]),
                                        SimpleNamespace(data={'id': str(uuid4())}), SimpleNamespace(data=[])]
            request = Request({'type': 'http', 'headers': [], 'client': ('127.0.0.1', 123), 'state': {}})
            with patch.object(users, 'get_supabase_client', return_value=db), patch.object(users, 'get_settings', return_value=SimpleNamespace(normalized_frontend_url='https://app.example.org')):
                result = users.resend_password_invitation(request, uuid4(), SimpleNamespace(id=uuid4(), role_code=role))
            self.assertEqual(result, {'ok': True})
            db.auth.reset_password_for_email.assert_called_once_with('monitor@example.org', {'redirect_to': 'https://app.example.org/restablecer-password'})
            self.assertEqual(query.insert.call_args.args[0]['action'], 'REQUEST_USER_PASSWORD_INVITATION')

    def test_non_administrator_cannot_send(self):
        with patch.object(users, 'get_supabase_client') as db:
            with self.assertRaises(HTTPException) as error:
                users.resend_password_invitation(Request({'type': 'http'}), uuid4(), SimpleNamespace(role_code='COORDINADOR'))
            self.assertEqual(error.exception.status_code, 403)
            db.assert_not_called()

    def test_directiva_cannot_reset_superadmin(self):
        db = Mock()
        query = db.table.return_value.select.return_value.eq.return_value.is_.return_value
        query.execute.return_value.data = [{'activo': True, 'roles': {'codigo': 'SUPERADMIN'}}]
        with patch.object(users, 'get_supabase_client', return_value=db):
            with self.assertRaises(HTTPException) as error:
                users.resend_password_invitation(Request({'type': 'http'}), uuid4(), SimpleNamespace(role_code='DIRECTIVA'))
        self.assertEqual(error.exception.status_code, 403)
        db.auth.reset_password_for_email.assert_not_called()
