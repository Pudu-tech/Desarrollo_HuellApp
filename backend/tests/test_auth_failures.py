"""HuellApp · Pruebas de errores de validación de sesión.

RESPONSABILIDADES
------------------------------------------------------------
- Verificar errores de validación de sesión mediante casos de regresión.

ESTADO ACTUAL
------------------------------------------------------------
- Suite local basada en unittest y colaboradores simulados.

SECURITY
------------------------------------------------------------
Utiliza simulaciones de los servicios externos. No introducir credenciales
reales ni ejecutar estas pruebas contra datos de producción.
"""
import unittest
from unittest.mock import Mock, patch
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from supabase_auth.errors import AuthApiError
from app.core import security


class AuthFailureTests(unittest.TestCase):
    def test_transient_failure_is_not_invalid_session(self):
        db = Mock()
        db.auth.get_user.side_effect = RuntimeError('temporary network error')
        with patch.object(security, 'get_supabase_client', return_value=db), self.assertRaises(HTTPException) as error:
            security.get_current_user(HTTPAuthorizationCredentials(scheme='Bearer', credentials='test'))
        self.assertEqual(error.exception.status_code, 503)

    def test_invalid_token_remains_unauthorized(self):
        db = Mock()
        db.auth.get_user.side_effect = AuthApiError('invalid token', 401, None)
        with patch.object(security, 'get_supabase_client', return_value=db), self.assertRaises(HTTPException) as error:
            security.get_current_user(HTTPAuthorizationCredentials(scheme='Bearer', credentials='test'))
        self.assertEqual(error.exception.status_code, 401)
