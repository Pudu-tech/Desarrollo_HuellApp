import unittest
from app.services.participation_notifications import project_personal_summary


class ParticipationDateTests(unittest.TestCase):
    def project(self, invitations, state='PENDIENTE'):
        return project_personal_summary({
            'id': 'participant', 'invitacion_version': 'current',
            'created_at': '2026-10-07T18:00:00+00:00',
            'notificaciones': invitations, 'estados_participacion': {'codigo': state},
        }, {
            'fecha': '2026-11-01', 'hora_inicio': '09:00', 'hora_fin': '10:00',
            'lugar': 'Lugar', 'observacion': None, 'activo': True,
            'estados_asignacion': {'codigo': 'PENDIENTE'},
        }, 'assignment')

    def test_first_invitation_uses_participant_creation_not_activity_date(self):
        result = self.project([{'invitacion_version': 'current', 'created_at': '2026-10-07T18:00:00+00:00'}])
        self.assertEqual(result['recibida_at'], '2026-10-07T18:00:00+00:00')
        self.assertIsNone(result['actualizada_at'])
        self.assertEqual(result['fecha'], '2026-11-01')

    def test_reconfirmation_preserves_original_and_uses_current_version(self):
        invitations = [{'invitacion_version': 'old', 'created_at': '2026-10-07T18:00:00+00:00'},
                       {'invitacion_version': 'current', 'created_at': '2026-10-08T20:00:00+00:00'}]
        pending = self.project(invitations)
        rejected = self.project(invitations, 'RECHAZADA')
        self.assertEqual(pending['actualizada_at'], '2026-10-08T20:00:00+00:00')
        self.assertEqual(pending['ultima_invitacion_at'], rejected['ultima_invitacion_at'])
        self.assertEqual(pending['recibida_at'], '2026-10-07T18:00:00+00:00')

    def test_legacy_without_notification_retains_creation_date(self):
        result = self.project([])
        self.assertEqual(result['ultima_invitacion_at'], result['recibida_at'])
        self.assertIsNone(result['actualizada_at'])
