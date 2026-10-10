import unittest
from datetime import date
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from app.api.audit import list_audit_logs, router

class AuditReadTests(unittest.TestCase):
    def test_invalid_dates_are_rejected_before_query(self):
        with self.assertRaises(HTTPException) as error:
            list_audit_logs(desde=date(2026,10,10), hasta=date(2026,10,9))
        self.assertEqual(error.exception.status_code, 422)

    def test_pagination_and_chilean_day_boundaries(self):
        db = MagicMock()
        query = db.table.return_value
        for method in ('select','gte','lt','order','range'):
            getattr(query,method).return_value = query
        query.execute.return_value.data = []
        with patch('app.api.audit.get_supabase_client',return_value=db):
            result = list_audit_logs(limit=26,offset=25,action=None,entity_type=None,actor_user_id=None,actor_role_id=None,desde=date(2026,10,9),hasta=date(2026,10,9),search=None,asignacion=None,current_user=None)
        self.assertEqual(result, [])
        query.gte.assert_called_once_with('created_at','2026-10-09T00:00:00-03:00')
        query.lt.assert_called_once_with('created_at','2026-10-10T00:00:00-03:00')
        query.range.assert_called_once_with(25,50)

    def test_routes_only_allow_read_operations(self):
        for route in router.routes:
            self.assertEqual(route.methods, {'GET'})
            self.assertTrue(route.dependant.dependencies)
