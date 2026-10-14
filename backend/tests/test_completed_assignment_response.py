import unittest
from datetime import datetime, timezone
from app.services.participation_notifications import response_available


class CompletedResponseTests(unittest.TestCase):
    def test_completed_activity_accepts_response_until_attendance_deadline(self):
        assignment = {'activo': True, 'fecha': '2026-10-09', 'hora_fin': '09:00', 'estados_asignacion': {'codigo': 'REALIZADA'}}
        self.assertTrue(response_available(assignment, datetime(2026, 10, 9, 22, tzinfo=timezone.utc)))
        self.assertFalse(response_available(assignment, datetime(2026, 10, 10, 12, tzinfo=timezone.utc)))
        assignment['estados_asignacion']['codigo'] = 'CANCELADA'
        self.assertFalse(response_available(assignment, datetime(2026, 10, 9, 22, tzinfo=timezone.utc)))
