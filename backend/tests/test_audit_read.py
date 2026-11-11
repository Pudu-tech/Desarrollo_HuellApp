"""HuellApp · Pruebas de permisos, filtros y ordenación de auditoría.

RESPONSABILIDADES
------------------------------------------------------------
- Verificar permisos, filtros y ordenación de auditoría mediante casos de regresión.

ESTADO ACTUAL
------------------------------------------------------------
- Suite local basada en unittest y colaboradores simulados.

SECURITY
------------------------------------------------------------
Utiliza simulaciones de los servicios externos. No introducir credenciales
reales ni ejecutar estas pruebas contra datos de producción.
"""
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

    def test_actor_sort_orders_all_results_before_pagination(self):
        db = MagicMock()
        query = db.table.return_value
        for method in ('select', 'order', 'range'):
            getattr(query, method).return_value = query
        query.execute.return_value.data = []
        with patch('app.api.audit.get_supabase_client', return_value=db):
            result = list_audit_logs(limit=26, offset=25, action=None, entity_type=None,
                actor_user_id=None, actor_role_id=None, desde=None, hasta=None,
                search=None, asignacion=None, sort_by='actor', sort_direction='asc', current_user=None)
        self.assertEqual(result, [])
        self.assertIn('actor:usuarios!fk_audit_logs_actor_user', query.select.call_args.args[0])
        self.assertEqual([call.args[0] for call in query.order.call_args_list],
            ['actor(nombres)', 'actor(apellido_paterno)', 'actor(apellido_materno)', 'created_at', 'id'])
        self.assertTrue(all(call.kwargs['desc'] is False for call in query.order.call_args_list))
        query.range.assert_called_once_with(25, 50)
        methods = [call[0] for call in query.mock_calls]
        self.assertGreater(methods.index('range'), max(i for i, method in enumerate(methods) if method == 'order'))

    def test_date_sort_can_start_with_oldest_without_changing_filter_scope(self):
        db = MagicMock()
        query = db.table.return_value
        for method in ('select', 'order', 'range', 'eq'):
            getattr(query, method).return_value = query
        query.execute.return_value.data = []
        with patch('app.api.audit.get_supabase_client', return_value=db):
            list_audit_logs(limit=26, offset=0, action='CREATE_ASSIGNMENT', entity_type=None,
                actor_user_id=None, actor_role_id=None, desde=None, hasta=None,
                search=None, asignacion=None, sort_by='fecha', sort_direction='asc', current_user=None)
        query.eq.assert_called_once_with('action', 'CREATE_ASSIGNMENT')
        self.assertEqual([call.args[0] for call in query.order.call_args_list], ['created_at', 'id'])
        self.assertTrue(all(call.kwargs['desc'] is False for call in query.order.call_args_list))

    def test_routes_only_allow_read_operations(self):
        for route in router.routes:
            self.assertEqual(route.methods, {'GET'})
            self.assertTrue(route.dependant.dependencies)

    def test_http_sort_parameters_are_validated_before_database_access(self):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        app = FastAPI()
        app.include_router(router)
        route = next(route for route in router.routes if route.path == '/audit')
        app.dependency_overrides[route.dependant.dependencies[0].call] = lambda: None
        client = TestClient(app)
        with patch('app.api.audit.get_supabase_client') as db:
            self.assertEqual(client.get('/audit?sort_by=unknown').status_code, 422)
            self.assertEqual(client.get('/audit?sort_direction=invalid').status_code, 422)
            db.assert_not_called()
