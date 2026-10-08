"""Respuesta única rechazada y proyección de participantes, sin escrituras externas."""
import unittest
from app.api.asignaciones import _por_reasignar, _participante_detalle


class AssignmentResponseSummaryTests(unittest.TestCase):
    def test_single_rejection_requires_reassignment_only_while_pending(self):
        assignment = {"activo": True, "estado": {"codigo": "PENDIENTE"}}
        rejected = {"activo": True, "estado": {"codigo": "RECHAZADA"}}
        self.assertTrue(_por_reasignar(assignment, [rejected]))
        for code in ("CONFIRMADA", "CANCELADA", "REALIZADA", "NO_REALIZADA"):
            self.assertFalse(_por_reasignar({**assignment, "estado": {"codigo": code}}, [rejected]))
        self.assertFalse(_por_reasignar({**assignment, "activo": False}, [rejected]))

    def test_archived_participants_do_not_change_single_current_response(self):
        assignment = {"activo": True, "estado": {"codigo": "PENDIENTE"}}
        rejected = {"activo": True, "estado": {"codigo": "RECHAZADA"}}
        pending = {"activo": True, "estado": {"codigo": "PENDIENTE"}}
        self.assertTrue(_por_reasignar(assignment, [rejected, {**pending, "deleted_at": "2026-10-07"}]))
        self.assertFalse(_por_reasignar(assignment, [rejected, pending]))
        self.assertFalse(_por_reasignar(assignment, [pending]))
        self.assertFalse(_por_reasignar(assignment, []))

    def test_readable_response_preserves_reason_and_limits_user_fields(self):
        result = _participante_detalle({"usuario": {"nombres": "Ana", "apellido_paterno": "Pérez", "apellido_materno": None},
                                       "tipo": {"nombre": "Relator"}, "estado": {"codigo": "RECHAZADA", "nombre": "Rechazada"},
                                       "motivo_rechazo": "No disponible"})
        self.assertEqual(result["usuario_nombre"], "Ana Pérez")
        self.assertEqual(result["estado_participacion_codigo"], "RECHAZADA")
        self.assertEqual(result["motivo_rechazo"], "No disponible")
        self.assertIsNone(_participante_detalle({})["usuario_nombre"])
