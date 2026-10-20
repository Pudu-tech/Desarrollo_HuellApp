"""Seguridad y límites del procesamiento HTTP; sin envíos ni llamadas reales."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app.api import notification_dispatch as api
from app.workers import notifications as worker


class DispatchTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(api.router)
        self.client = TestClient(app)
        self.settings = SimpleNamespace(
            notification_webhook_secret=SecretStr('webhook-' * 8),
            cron_secret=SecretStr('cron-' * 8))
        self.config_patch = patch.object(api, 'get_settings', return_value=self.settings)
        self.config_patch.start()
        self.addCleanup(self.config_patch.stop)

    def headers(self, field):
        return {'Authorization': 'Bearer ' + getattr(self.settings, field).get_secret_value()}

    def test_unauthorized_requests_never_touch_queue(self):
        with patch.object(api, 'dispatch') as dispatch:
            self.assertEqual(self.client.post('/internal/notifications/webhook').status_code, 401)
            self.assertEqual(self.client.get('/internal/notifications/cron').status_code, 401)
            self.assertEqual(self.client.post('/internal/notifications/webhook',
                headers=self.headers('cron_secret')).status_code, 401)
            dispatch.assert_not_called()

    def test_missing_secret_fails_closed(self):
        self.settings.notification_webhook_secret = None
        with patch.object(api, 'dispatch') as dispatch:
            self.assertEqual(self.client.post('/internal/notifications/webhook').status_code, 503)
            dispatch.assert_not_called()

    def test_webhook_uses_queue_and_ignores_payload(self):
        with patch.object(api, 'dispatch', return_value={'procesadas': 1}) as dispatch:
            result = self.client.post('/internal/notifications/webhook',
                headers=self.headers('notification_webhook_secret'),
                json={'record': {'email': 'untrusted@example.org'}})
            self.assertEqual(result.json(), {'procesadas': 1})
            self.assertEqual(result.headers['cache-control'], 'no-store')
            dispatch.assert_called_once_with(self.settings, max_jobs=1)

    def test_cron_uses_finite_batch_and_cannot_be_cached(self):
        with patch.object(api, 'dispatch', return_value={'procesadas': 0}) as dispatch:
            result = self.client.get('/internal/notifications/cron', headers=self.headers('cron_secret'))
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.headers['cache-control'], 'no-store')
            dispatch.assert_called_once_with(self.settings, max_jobs=100)

    def test_bad_provider_configuration_does_not_reserve_jobs(self):
        with patch.object(api, 'check_configuration', side_effect=RuntimeError('private')), \
             patch.object(api, 'get_supabase_client') as db:
            result = self.client.post('/internal/notifications/webhook',
                headers=self.headers('notification_webhook_secret'))
            self.assertEqual(result.status_code, 503)
            self.assertNotIn('private', result.text)
            db.assert_not_called()

    def test_batch_exception_is_sanitized(self):
        with patch.object(api, 'check_configuration'), patch.object(api, 'get_supabase_client'), \
             patch.object(api.httpx, 'Client'), \
             patch.object(api, 'process_batch', side_effect=RuntimeError('private')):
            result = self.client.get('/internal/notifications/cron', headers=self.headers('cron_secret'))
            self.assertEqual(result.status_code, 503)
            self.assertNotIn('private', result.text)

    def test_batch_stops_on_empty_queue_without_sleep(self):
        with patch.object(worker, 'process_one', side_effect=[True, False]) as process, \
             patch.object(worker.time, 'sleep') as sleep:
            self.assertEqual(worker.process_batch(Mock(), Mock(), Mock()), 1)
            self.assertEqual(process.call_count, 2)
            sleep.assert_not_called()

    def test_batch_honors_job_limit(self):
        with patch.object(worker, 'process_one', return_value=True) as process:
            self.assertEqual(worker.process_batch(Mock(), Mock(), Mock(), max_jobs=3), 3)
            self.assertEqual(process.call_count, 3)

    def test_batch_does_not_start_more_jobs_after_deadline(self):
        with patch.object(worker.time, 'monotonic', side_effect=[0, 0, 181]), \
             patch.object(worker, 'process_one', return_value=True) as process:
            self.assertEqual(worker.process_batch(Mock(), Mock(), Mock()), 1)
            self.assertEqual(process.call_count, 1)


if __name__ == '__main__':
    unittest.main()
