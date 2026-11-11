"""Recordatorios: elegibilidad, contenido, supresión y generación autenticada sin enviar correos reales."""
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch

from app.api import notification_dispatch as dispatch
from app.services.participation_notifications import reminder_available
from app.workers import notifications as worker


class ReminderTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 11, 10, 12, tzinfo=timezone.utc)
        self.part = {'estados_participacion': {'codigo': 'PENDIENTE'}}
        self.assignment = {'activo': True, 'fecha': '2026-11-13',
                           'estados_asignacion': {'codigo': 'CONFIRMADA'}}
        self.notification = {'id': 'notification', 'entidad_id': 'assignment',
                             'usuario_destino_id': 'user', 'invitacion_version': 'version',
                             'tipo_notificacion': worker.REMINDER_TYPE,
                             'recordatorio_fecha': '2026-11-13',
                             'titulo': 'Recordatorio: tu instancia es en tres días'}
        self.own = {'actividad': '<Actividad>', 'fecha': '2026-11-13', 'hora_inicio': '09:00',
                    'hora_fin': '10:00', 'colegio': None, 'lugar': 'Sede', 'curso': None,
                    'sala': None, 'asignatura': None, 'estado': 'ACEPTADA',
                    'admite_recordatorio': True, 'admite_respuesta': False}
        self.settings = SimpleNamespace(normalized_frontend_url='https://app.example.org',
                                        brevo_sender_name='HuellApp', brevo_sender_email='sender@example.org',
                                        brevo_api_key=Mock(get_secret_value=lambda: 'test-key'))
        self.recipient = {'email': 'test@example.org', 'nombres': 'Persona'}

    def test_three_calendar_days_for_pending_and_accepted(self):
        for state in ('PENDIENTE', 'ACEPTADA'):
            self.part['estados_participacion']['codigo'] = state
            self.assertTrue(reminder_available(self.part, self.assignment, self.now))
        self.part['estados_participacion']['codigo'] = 'RECHAZADA'
        self.assertFalse(reminder_available(self.part, self.assignment, self.now))

    def test_santiago_date_not_utc_date_in_summer_and_winter(self):
        self.assertFalse(reminder_available(self.part, self.assignment,
                         datetime(2026, 11, 10, 2, 59, tzinfo=timezone.utc)))
        self.assertTrue(reminder_available(self.part, self.assignment,
                        datetime(2026, 11, 10, 3, tzinfo=timezone.utc)))
        self.assignment['fecha'] = '2026-07-13'
        self.assertFalse(reminder_available(self.part, self.assignment,
                         datetime(2026, 7, 10, 3, 59, tzinfo=timezone.utc)))
        self.assertTrue(reminder_available(self.part, self.assignment,
                        datetime(2026, 7, 10, 4, tzinfo=timezone.utc)))

    def test_other_dates_and_closed_instances_are_ineligible(self):
        for date in ('2026-11-12', '2026-11-14'):
            self.assignment['fecha'] = date
            self.assertFalse(reminder_available(self.part, self.assignment, self.now))
        self.assignment['fecha'] = '2026-11-13'
        for state in ('CANCELADA', 'REALIZADA', 'NO_REALIZADA'):
            self.assignment['estados_asignacion']['codigo'] = state
            self.assertFalse(reminder_available(self.part, self.assignment, self.now))
        self.assignment['estados_asignacion']['codigo'] = 'PENDIENTE'
        self.assignment['deleted_at'] = '2026-11-10'
        self.assertFalse(reminder_available(self.part, self.assignment, self.now))

    def message(self):
        with patch.object(worker, 'invitation_token', return_value='signed-token'):
            return worker.build_message(self.settings, self.notification, self.own, self.recipient, 'delivery')

    def test_accepted_reminder_has_detail_link_without_response_buttons(self):
        payload = self.message()
        self.assertIn('Ya confirmaste', payload['htmlContent'])
        self.assertIn('Ver detalle de la instancia', payload['htmlContent'])
        self.assertNotIn('Aceptar participación', payload['htmlContent'])
        self.assertNotIn('Rechazar participación', payload['htmlContent'])
        self.assertNotIn('accion=', payload['htmlContent'])
        self.assertIn('&lt;Actividad&gt;', payload['htmlContent'])
        self.assertEqual(payload['headers']['idempotencyKey'], 'delivery')

    def test_pending_reminder_keeps_response_buttons(self):
        self.own['estado'] = 'PENDIENTE'
        payload = self.message()
        self.assertIn('Aceptar participación', payload['htmlContent'])
        self.assertIn('Rechazar participación', payload['htmlContent'])
        self.assertIn('en tres días', payload['textContent'])

    def process(self):
        db = Mock()
        job = {'envio': {'id': 'delivery', 'reserva_id': 'lease'}, 'notificacion': self.notification}
        db.rpc.side_effect = lambda name, args: SimpleNamespace(
            execute=lambda: SimpleNamespace(data=job if name == 'reservar_envio_participacion' else True))
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.is_.return_value.execute.return_value.data = [self.recipient]
        client = Mock()
        client.post.return_value.status_code = 201
        client.post.return_value.is_success = True
        client.post.return_value.json.return_value = {'messageId': 'provider-id'}
        with patch.object(worker, 'personal_summary', return_value=self.own), \
             patch.object(worker, 'invitation_token', return_value='signed-token'):
            worker.process_one(db, self.settings, client)
        return db, client

    def test_accepted_participant_is_sent_reminder_without_response_available(self):
        db, client = self.process()
        client.post.assert_called_once()
        self.assertEqual(db.rpc.call_args.args[1]['p_estado'], 'ENVIADA')

    def test_change_between_reservation_and_send_suppresses_reminder(self):
        for change in ({'admite_recordatorio': False}, {'fecha': '2026-11-14'}):
            with self.subTest(change=change):
                original = self.own.copy()
                self.own.update(change)
                db, client = self.process()
                client.post.assert_not_called()
                self.assertEqual(db.rpc.call_args.args[1]['p_estado'], 'CANCELADA')
                self.own = original

    def test_cron_enqueues_before_dispatch_but_webhook_does_not(self):
        db = Mock()
        with patch.object(dispatch, 'check_configuration'), \
             patch.object(dispatch, 'get_supabase_client', return_value=db), \
             patch.object(dispatch.httpx, 'Client'), \
             patch.object(dispatch, 'process_batch', return_value=0) as process:
            process.side_effect = lambda *args, **kwargs: (
                self.assertEqual(db.rpc.call_args.args[0], 'encolar_recordatorios_instancias') or 0)
            dispatch.dispatch(self.settings, max_jobs=100, enqueue_reminders=True)
            db.rpc.assert_called_once_with('encolar_recordatorios_instancias', {})
            db.reset_mock()
            process.side_effect = None
            dispatch.dispatch(self.settings, max_jobs=1)
            db.rpc.assert_not_called()


if __name__ == '__main__':
    unittest.main()
