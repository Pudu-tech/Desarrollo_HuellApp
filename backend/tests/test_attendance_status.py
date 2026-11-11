"""HuellApp · Pruebas de estado operativo de asistencia.

RESPONSABILIDADES
------------------------------------------------------------
- Verificar estado operativo de asistencia mediante casos de regresión.

ESTADO ACTUAL
------------------------------------------------------------
- Suite local basada en unittest y colaboradores simulados.

SECURITY
------------------------------------------------------------
Utiliza simulaciones de los servicios externos. No introducir credenciales
reales ni ejecutar estas pruebas contra datos de producción.
"""
import unittest
from app.services.attendance_status import effective_attendance_state
from app.api.asignaciones import _attendance_counts


class AttendanceStatusTests(unittest.TestCase):
    def test_rejection_does_not_require_pending_attendance(self):
        self.assertEqual(effective_attendance_state('PENDIENTE', 'RECHAZADA'), 'NO_REQUERIDA')

    def test_reopening_and_reported_history(self):
        self.assertEqual(effective_attendance_state('PENDIENTE', 'PENDIENTE'), 'PENDIENTE')
        self.assertEqual(effective_attendance_state('PRESENTE', 'RECHAZADA'), 'PRESENTE')

    def test_assignment_summary_separates_rejected_participant(self):
        rows = [{'activo': True, 'estado': {'codigo': 'RECHAZADA'}, 'asistencia': [{'estado': 'PENDIENTE'}]},
                {'activo': True, 'estado': {'codigo': 'ACEPTADA'}, 'asistencia': [{'estado': 'PENDIENTE'}]}]
        self.assertEqual(_attendance_counts(rows), {'NO_REQUERIDA': 1, 'PENDIENTE': 1})
