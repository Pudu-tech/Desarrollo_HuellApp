"""HuellApp · Disparadores HTTP de la cola de correos.

RESPONSABILIDADES
------------------------------------------------------------
- Ejecutar lotes acotados del worker desde el webhook o el cron.

ESTADO ACTUAL
------------------------------------------------------------
- Webhook de un trabajo; cron de hasta cien, con reservas gestionadas por el worker.

SECURITY
------------------------------------------------------------
Cada disparador valida su secreto Bearer. El cuerpo recibido no define
destinatarios ni contenido; los mensajes se leen de la cola persistida.

NOTAS DE IMPLEMENTACIÓN
------------------------------------------------------------
Procesamiento acotado de la cola de correos desde Vercel.

Expone disparadores autenticados para Supabase Webhooks y Cron. Los mensajes
se leen únicamente de la cola; el cuerpo del webhook no define destinatarios.
Las reservas y los estados de entrega se gestionan en el worker compartido.
"""
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
    """Valida Bearer con comparación constante y rechaza secretos sin configurar."""
    value = secret.get_secret_value() if secret else ''
    if len(value) < 32:
        raise HTTPException(503, 'El procesamiento de correos no está configurado.')
    expected = f'Bearer {value}'.encode('utf-8')
    if not authorization or not compare_digest(authorization.encode('utf-8'), expected):
        raise HTTPException(401, 'No autorizado.')


def dispatch(settings, *, max_jobs, enqueue_reminders=False):
    """Procesa un lote limitado; el contador indica trabajos procesados, no entregas confirmadas."""
    try:
        # Validar antes de reservar entregas. La cola es la única fuente de datos:
        # no se usan destinatarios ni contenido del cuerpo recibido por webhook.
        check_configuration(settings)
        db = get_supabase_client()
        if enqueue_reminders:
            db.rpc('encolar_recordatorios_instancias', {}).execute()
        with httpx.Client(timeout=30) as client:
            processed = process_batch(db, settings, client, max_jobs=max_jobs, max_seconds=180)
    except Exception:
        # Sin traceback ni cuerpos del proveedor que puedan contener secretos.
        logger.error('No se pudo completar el lote de correos; revisar la cola.')
        raise HTTPException(503, 'No se pudo completar el lote de correos.') from None
    return {'procesadas': processed}


@router.post('/webhook')
def notification_webhook(response: Response, authorization: str | None = Header(default=None)):
    """Atiende un aviso de inserción intentando procesar un trabajo pendiente de la cola."""
    settings = get_settings()
    authorize(authorization, settings.notification_webhook_secret)
    response.headers['Cache-Control'] = 'no-store'
    # Un aviso por INSERT. Las reservas SQL protegen contra avisos duplicados
    # y ejecuciones simultáneas, incluido el worker CLI existente.
    return dispatch(settings, max_jobs=1)


@router.get('/cron')
def notification_cron(response: Response, authorization: str | None = Header(default=None)):
    """Procesa pendientes en un lote mayor usando el secreto independiente de Cron."""
    settings = get_settings()
    authorize(authorization, settings.cron_secret)
    response.headers['Cache-Control'] = 'no-store'
    return dispatch(settings, max_jobs=100, enqueue_reminders=True)
