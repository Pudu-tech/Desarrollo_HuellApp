import unittest
from datetime import date
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from app.api.audit import list_audit_logs, router, search_audit, display_audit_references

class AuditReadTests(unittest.TestCase):
    def test_reference_display_preserves_original_audit_values(self):
        identifier = '11111111-1111-4111-8111-111111111111'
        rows = [{'old_values': {'estado_participacion_id': identifier}, 'new_values': {'estado_participacion_id': identifier}}]
        db = MagicMock()
        db.table.return_value.select.return_value.in_.return_value.execute.return_value.data = [{'id': identifier, 'nombre': 'Pendiente'}]
        display_audit_references(db, rows)
        self.assertEqual(rows[0]['old_values']['estado_participacion_id'], identifier)
        self.assertEqual(rows[0]['old_display_values']['estado_participacion_id'], 'Pendiente')
        self.assertEqual(rows[0]['new_display_values']['estado_participacion_id'], 'Pendiente')
        db.table.assert_called_once_with('estados_participacion')
    def test_delete_search_matches_action_and_description(self):
        db = MagicMock()
        db.table.return_value.select.return_value.or_.return_value.execute.return_value.data = []
        query = MagicMock()
        search_audit(query, db, 'eliminar')
        clauses = query.or_.call_args.args[0]
        self.assertIn('action.ilike."DELETE_%"', clauses)
        self.assertIn('description.ilike."%elimin%"', clauses)

    def test_search_quotes_postgrest_syntax(self):
        db = MagicMock()
        db.table.return_value.select.return_value.or_.return_value.execute.return_value.data = []
        query = MagicMock()
        search_audit(query, db, 'x),action.eq.DELETE_USER')
        self.assertIn('description.ilike."%x),action.eq.DELETE\\\\_USER%"', query.or_.call_args.args[0])
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
