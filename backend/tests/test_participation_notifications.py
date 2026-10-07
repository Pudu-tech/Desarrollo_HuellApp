"""Firma, transporte y fallos de correo sin enviar mensajes ni usar credenciales."""
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4
import httpx
import jwt
from pydantic import SecretStr, ValidationError
from fastapi import HTTPException
from app.services import participation_notifications as service
from app.workers import notifications as worker
from app.api.participation_notifications import ParticipationResponse, InvitationResponse, respond


class NotificationTests(unittest.TestCase):
    def setUp(self):
        self.settings = SimpleNamespace(notification_token_secret=SecretStr('test-key-' * 8),
            brevo_notifications_enabled=True, brevo_api_key=SecretStr('test-api-key'),
            brevo_sender_name='HuellApp', brevo_sender_email='sender@example.org', normalized_frontend_url='https://app.example.org')
        self.notification = {'id': str(uuid4()), 'usuario_destino_id': str(uuid4()),
            'participacion_id': str(uuid4()), 'invitacion_version': str(uuid4()), 'entidad_id': str(uuid4()),
            'activo': True, 'expires_at': (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()}
        self.own = {'actividad': '<script>test</script>', 'fecha': '2026-12-01', 'hora_inicio': '09:00', 'hora_fin': '10:00',
                    'colegio': 'Colegio', 'lugar': None, 'curso': None, 'sala': None, 'asignatura': None, 'admite_respuesta': True}

    def test_token_firmado_no_admite_firma_ajena_o_vencimiento(self):
        db = Mock()
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = [self.notification]
        with patch.object(service, 'get_settings', return_value=self.settings):
            token = service.invitation_token(self.notification)
            self.assertEqual(service.verify_invitation(db, token)['id'], self.notification['id'])
            claims = jwt.decode(token, options={'verify_signature': False})
            wrong = jwt.encode(claims, 'foreign-secret-' * 5, algorithm='HS256')
            with self.assertRaises(HTTPException) as error:
                service.verify_invitation(db, wrong)
            self.assertEqual(error.exception.status_code, 410)
            self.notification['expires_at'] = (datetime.now(timezone.utc) - timedelta(seconds=10)).isoformat()
            with self.assertRaises(HTTPException):
                service.verify_invitation(db, service.invitation_token(self.notification))

    def test_correo_escapa_html_y_coloca_token_en_fragmento(self):
        with patch.object(service, 'get_settings', return_value=self.settings):
            payload = worker.build_message(self.settings, self.notification, self.own,
                       {'email': 'participant@example.org', 'nombres': 'Persona'}, 'delivery-id')
        self.assertNotIn('<script>test</script>', payload['htmlContent'])
        self.assertIn('&lt;script&gt;', payload['htmlContent'])
        self.assertIn('/responder-participacion#token=', payload['htmlContent'])
        self.assertEqual(payload['headers']['idempotencyKey'], 'delivery-id')

    def test_body_no_admite_actor_canal_y_rechazo_requiere_motivo(self):
        with self.assertRaises(ValidationError):
            InvitationResponse(token='x'*30, accion='ACCEPT', canal='WHATSAPP')
        with self.assertRaises(ValidationError):
            ParticipationResponse(accion='REJECT', motivo=' ')
        with self.assertRaises(ValidationError):
            ParticipationResponse(accion='ACCEPT', actor_id=str(uuid4()))

    def test_respuesta_previa_se_devuelve_sin_cambiarla(self):
        db = Mock()
        db.rpc.return_value.execute.return_value.data = {'ok': True, 'estado': 'RECHAZADA', 'ya_respondida': True}
        request = SimpleNamespace(state=SimpleNamespace(), client=None, headers={})
        result = respond(db, request, uuid4(), uuid4(), uuid4(), ParticipationResponse(accion='ACCEPT'), 'WEB')
        self.assertEqual(result, {'estado': 'RECHAZADA', 'ya_respondida': True})

    def test_timeout_queda_incierto_y_no_pendiente_para_reenvio(self):
        db = Mock()
        delivery = {'id': str(uuid4()), 'reserva_id': str(uuid4())}
        def rpc(name, params):
            return SimpleNamespace(execute=lambda: SimpleNamespace(data={'envio': delivery, 'notificacion': self.notification} if name=='reservar_envio_participacion' else True))
        db.rpc.side_effect = rpc
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.is_.return_value.execute.return_value.data = [{'email': 'p@example.org', 'nombres': 'Persona'}]
        client = Mock()
        client.post.side_effect = httpx.ReadTimeout('timeout')
        with patch.object(worker, 'personal_summary', return_value=self.own), patch.object(service, 'get_settings', return_value=self.settings):
            self.assertTrue(worker.process_one(db, self.settings, client))
        name, args = db.rpc.call_args.args
        self.assertEqual(name, 'finalizar_envio_participacion')
        self.assertEqual(args['p_estado'], 'INCIERTA')


if __name__ == '__main__':
    unittest.main()
