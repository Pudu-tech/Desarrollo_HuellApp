"""Ejecuciones finitas del worker para Supabase Webhooks y Vercel Cron."""
import logging
from secrets import compare_digest

import httpx
from fastapi import APIRouter, Header, HTTPException, Response

from app.core.config import get_settings
from app.core.supabase import get_supabase_client
from app.workers.notifications import check_configuration, process_batch

router = APIRouter(prefix='/internal/notifications', include_in_schema=False)
logger = logging.getLogger(__name__)


def authorize(authorization, secret):
    value = secret.get_secret_value() if secret else ''
    if len(value) < 32:
        raise HTTPException(503, 'El procesamiento de correos no está configurado.')
    expected = f'Bearer {value}'.encode('utf-8')
    if not authorization or not compare_digest(authorization.encode('utf-8'), expected):
        raise HTTPException(401, 'No autorizado.')


def dispatch(settings, *, max_jobs):
    try:
        # Validar antes de reservar entregas. La cola es la única fuente de datos:
        # no se usan destinatarios ni contenido del cuerpo recibido por webhook.
        check_configuration(settings)
        db = get_supabase_client()
        with httpx.Client(timeout=30) as client:
            processed = process_batch(db, settings, client, max_jobs=max_jobs, max_seconds=180)
    except Exception:
        # Sin traceback ni cuerpos del proveedor que puedan contener secretos.
        logger.error('No se pudo completar el lote de correos; revisar la cola.')
        raise HTTPException(503, 'No se pudo completar el lote de correos.') from None
    return {'procesadas': processed}


@router.post('/webhook')
def notification_webhook(response: Response, authorization: str | None = Header(default=None)):
    settings = get_settings()
    authorize(authorization, settings.notification_webhook_secret)
    response.headers['Cache-Control'] = 'no-store'
    # Un aviso por INSERT. Las reservas SQL protegen contra avisos duplicados
    # y ejecuciones simultáneas, incluido el worker CLI existente.
    return dispatch(settings, max_jobs=1)


@router.get('/cron')
def notification_cron(response: Response, authorization: str | None = Header(default=None)):
    settings = get_settings()
    authorize(authorization, settings.cron_secret)
    response.headers['Cache-Control'] = 'no-store'
    return dispatch(settings, max_jobs=100)
