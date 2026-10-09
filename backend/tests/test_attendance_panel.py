import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from fastapi import HTTPException
from app.api import asistencias, asignaciones
from app.services import attendance_location


class AttendanceTests(unittest.TestCase):
    def test_monitor_cannot_read_administrative_panel_even_if_permission_granted(self):
        with self.assertRaises(HTTPException) as error:
            asistencias.listar(SimpleNamespace(role_code='MONITOR'))
        self.assertEqual(error.exception.status_code, 403)

    def test_coordinator_cannot_regularize_even_if_permission_granted(self):
        with self.assertRaises(HTTPException) as error:
            asignaciones.regularizar_asistencia(None, None, None, None, SimpleNamespace(role_code='COORDINADOR'))
        self.assertEqual(error.exception.status_code, 403)

    def test_panel_filters_deleted_assignment_and_normalizes_precision(self):
        db = Mock()
        query = db.table.return_value.select.return_value
        query.eq.return_value = query
        query.is_.return_value = query
        query.execute.return_value.data = [{'asistencia': [{'id': 'a', 'asignacion_participante_id': 'p',
            'estado': 'PRESENTE', 'precision_metros': 12, 'created_at': 'date', 'updated_at': 'date'}]}]
        with patch.object(asistencias, 'get_supabase_client', return_value=db):
            result = asistencias.listar(SimpleNamespace(role_code='COORDINADOR'))
        self.assertEqual(result[0]['asistencia'][0]['precision_gps'], 12)
        query.is_.assert_any_call('asignacion.deleted_at', 'null')
        self.assertIn('usuarios!fk_asignacion_participantes_usuario', db.table.return_value.select.call_args.args[0])

    def test_query_failure_returns_controlled_http_error(self):
        query = Mock()
        query.execute.side_effect = RuntimeError('query failed')
        with self.assertRaises(HTTPException) as error:
            asistencias._read(query)
        self.assertEqual(error.exception.status_code, 503)

    def test_geocoding_without_key_makes_no_external_request(self):
        with patch.object(attendance_location, 'get_settings', return_value=SimpleNamespace(google_maps_api_key=None)), patch.object(attendance_location.httpx, 'get') as get:
            self.assertIsNone(attendance_location.lookup_address(-33, -70))
        get.assert_not_called()

    def test_optional_address_failure_does_not_undo_report(self):
        db = Mock()
        db.table.side_effect = RuntimeError('temporary')
        with patch.object(attendance_location, 'lookup_address', return_value={'direccion_detectada': 'Dirección'}):
            attendance_location.enrich_attendance(db, 'participant', -33, -70)
