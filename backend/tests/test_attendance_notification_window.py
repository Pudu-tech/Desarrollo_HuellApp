import unittest
from datetime import datetime, timezone, timedelta
from app.services.participation_notifications import attendance_available


class AttendanceWindowTests(unittest.TestCase):
    def test_notification_starts_at_activity_start_and_expires_at_deadline(self):
        part = {'estados_participacion': {'codigo': 'ACEPTADA'}}
        assignment = {'activo': True, 'fecha': '2026-10-09', 'hora_inicio': '08:00', 'hora_fin': '09:00',
                      'estados_asignacion': {'codigo': 'CONFIRMADA'}}
        start = datetime(2026, 10, 9, 11, tzinfo=timezone.utc)
        deadline = start + timedelta(hours=25)
        self.assertFalse(attendance_available(part, assignment, 'PENDIENTE', start - timedelta(seconds=1)))
        self.assertTrue(attendance_available(part, assignment, 'PENDIENTE', start))
        self.assertTrue(attendance_available(part, assignment, 'PENDIENTE', deadline - timedelta(seconds=1)))
        self.assertFalse(attendance_available(part, assignment, 'PENDIENTE', deadline))
        self.assertFalse(attendance_available(part, assignment, 'PRESENTE', start))
        part['estados_participacion']['codigo'] = 'RECHAZADA'
        self.assertFalse(attendance_available(part, assignment, 'PENDIENTE', start))
