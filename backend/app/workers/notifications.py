"""HuellApp · Worker de correo transaccional.

RESPONSABILIDADES
------------------------------------------------------------
- Reservar trabajos, enviar a Brevo y actualizar resultados de procesamiento.

ESTADO ACTUAL
------------------------------------------------------------
- Admite CLI y lotes HTTP; resultados ambiguos quedan INCIERTA.

SECURITY
------------------------------------------------------------
Valida configuración antes de reservar y utiliza reservas excluyentes.
ENVIADA significa aceptación del proveedor, no entrega confirmada al buzón.

NOTAS DE IMPLEMENTACIÓN
------------------------------------------------------------
Worker Brevo: python -m app.workers.notifications [--once].

Reserva duradera y excluyente; no envía si falta configuración. Una caída o
timeout ambiguo queda INCIERTA y exige verificar Brevo antes de reenviar.
ENVIADA significa aceptada por Brevo, no confirmación de entrega al buzón.
"""
import argparse
import re
import time
from urllib.parse import urlencode, urlparse
import httpx
from app.core.config import get_settings
from app.core.supabase import get_supabase_client
from app.services.participation_notifications import invitation_token, personal_summary, signing_secret
from fastapi import HTTPException
from app.services.invitation_email import render_invitation_email

REMINDER_TYPE = 'RECORDATORIO_INSTANCIA_3_DIAS'


def check_configuration(settings):
    """Valida canal, remitente, URL y firma antes de reservar cualquier trabajo."""
    if not settings.brevo_notifications_enabled:
        raise RuntimeError("Los correos están deshabilitados. Configura BREVO_NOTIFICATIONS_ENABLED.")
    if not settings.brevo_api_key or not settings.brevo_api_key.get_secret_value() or not settings.brevo_sender_email:
        raise RuntimeError("Configura BREVO_API_KEY y BREVO_SENDER_EMAIL en el backend.")
    frontend = urlparse(settings.normalized_frontend_url)
    if frontend.scheme not in ("http", "https") or not frontend.netloc:
        raise RuntimeError("Configura FRONTEND_URL con una URL válida.")
    signing_secret()


def build_message(settings, notification, own, recipient, delivery_id):
    """HTML escapa todos los datos. Fragmento evita tokens en logs de navegación."""
    token = invitation_token(notification)
    base = settings.normalized_frontend_url + "/responder-participacion#"
    accept = base + urlencode({"token": token, "accion": "ACCEPT"})
    reject = base + urlencode({"token": token, "accion": "REJECT"})
    fields = [("Actividad", own["actividad"]), ("Fecha", own["fecha"]),
              ("Horario", f'{own["hora_inicio"][:5]} – {own["hora_fin"][:5]}'),
              ("Colegio / lugar", own["colegio"] or own["lugar"]),
              ("Curso", own["curso"]), ("Sala", own["sala"]), ("Asignatura", own["asignatura"]),
              ("Espacio", own.get("espacio")), ("Tu participación", own.get("tipo_participacion"))]
    title = notification.get('titulo') or 'Nueva instancia en HuellApp'
    title = re.sub(r'\basignaci[oó]n(?:es)?\b', lambda match: (
        ('Instancias' if match.group().lower().endswith('es') else 'Instancia')
        if match.group()[0].isupper() else
        ('instancias' if match.group().lower().endswith('es') else 'instancia')
    ), title, flags=re.IGNORECASE)
    reminder = notification.get('tipo_notificacion') == REMINDER_TYPE
    accepted = reminder and own.get('estado') == 'ACEPTADA'
    detail = base + urlencode({'token': token})
    content = render_invitation_email(settings.normalized_frontend_url, title, fields, accept, reject,
                                      getattr(settings, 'brevo_email_logo_url', None),
                                      reminder=reminder, accepted=accepted, detail_url=detail)
    text = '\n'.join(f'{label}: {value}' for label, value in fields if value)
    intro = ('Tu instancia es en tres días. Ya confirmaste tu participación.' if accepted else
             'Tu instancia es en tres días. Confirma tu participación.' if reminder else '')
    actions = (f'Ver instancia: {detail}' if accepted else f'Aceptar: {accept}\nRechazar: {reject}')
    return {"sender": {"name": settings.brevo_sender_name, "email": settings.brevo_sender_email},
            "to": [{"email": recipient["email"], "name": recipient["nombres"]}],
            "subject": title, "htmlContent": content,
            "textContent": f'HuellApp\n{intro}\n{text}\n{actions}\nLa asistencia se registra por separado.',
            "headers": {"idempotencyKey": delivery_id}}


def process_one(db, settings, client):
    """Reserva un trabajo y persiste el resultado; los fallos ambiguos no se reenvían a ciegas."""
    job = db.rpc("reservar_envio_participacion", {}).execute().data
    if not job:
        return False
    if job.get("omitido"):
        return True
    delivery, notification = job["envio"], job["notificacion"]
    def finish(state, message=None, external=None):
        saved = db.rpc("finalizar_envio_participacion", {"p_id": delivery["id"], "p_reserva": delivery["reserva_id"],
                      "p_estado": state, "p_error": message, "p_externo": external}).execute().data
        if saved is not True:
            raise RuntimeError("La reserva de envío perdió vigencia; revisar la entrega.")
    try:
        own = personal_summary(db, notification["entidad_id"], notification["usuario_destino_id"], notification["invitacion_version"])
        reminder = notification.get('tipo_notificacion') == REMINDER_TYPE
        if reminder and (not own.get('admite_recordatorio')
                         or notification.get('recordatorio_fecha') != own['fecha']):
            finish('CANCELADA', 'La instancia ya no cumple la regla del recordatorio.')
            return True
        if not reminder and not own["admite_respuesta"]:
            finish("CANCELADA", "La participación ya fue respondida.")
            return True
        recipients = db.table("usuarios").select("email,nombres").eq("id", notification["usuario_destino_id"]) \
            .eq("activo", True).is_("deleted_at", "null").execute().data or []
        if not recipients:
            finish("CANCELADA", "El destinatario ya no está activo.")
            return True
        payload = build_message(settings, notification, own, recipients[0], delivery["id"])
    except HTTPException:
        finish("CANCELADA", "La invitación no está disponible.")
        return True
    # Solo errores inequívocos se reintentan automáticamente. No guarda cuerpos
    # del proveedor: podrían contener correos, enlaces o secretos.
    try:
        response = client.post("https://api.brevo.com/v3/smtp/email", json=payload,
                               headers={"api-key": settings.brevo_api_key.get_secret_value(), "Accept": "application/json"})
    except httpx.RequestError:
        finish("INCIERTA", "No se pudo confirmar el resultado de Brevo; verificar antes de reenviar.")
        return True
    if response.status_code == 429:
        finish("PENDIENTE", "Brevo limitó temporalmente las solicitudes.")
    elif response.status_code >= 500:
        finish("INCIERTA", "Brevo respondió con un fallo ambiguo; verificar la entrega.")
    elif response.is_success:
        try:
            data = response.json()
            external = (data.get("messageId") or (data.get("messageIds") or [None])[0]) if isinstance(data, dict) else None
        except (ValueError, TypeError):
            external = None
        finish("ENVIADA", external=external)
    else:
        try:
            duplicate = response.json().get("code") == "duplicate_parameter"
        except (ValueError, AttributeError):
            duplicate = False
        if duplicate:
            finish("ENVIADA", "Brevo confirmó la clave de un envío previo.")
        else:
            finish("FALLIDA", f'Brevo rechazó la solicitud (HTTP {response.status_code}). Revisar destinatario/remitente/configuración.')
    return True


def process_batch(db, settings, client, *, max_jobs=100, max_seconds=180):
    """Lote finito para HTTP. El plazo impide iniciar nuevos trabajos, no cancela envíos."""
    deadline = time.monotonic() + max_seconds
    processed = 0
    while processed < max_jobs and time.monotonic() < deadline:
        if not process_one(db, settings, client):
            break
        processed += 1
    # Incluye cancelaciones; no es un contador de entregas al buzón.
    return processed


def main():
    """Ejecuta el worker CLI de forma continua o hasta agotar el lote indicado por --once."""
    parser = argparse.ArgumentParser(description="Cola de invitaciones por Brevo")
    parser.add_argument("--once", action="store_true", help="Procesa hasta 100 pendientes y termina")
    args = parser.parse_args()
    settings = get_settings()
    check_configuration(settings)  # No reserva filas si no está listo el canal.
    db = get_supabase_client()
    with httpx.Client(timeout=30) as client:
        count = 0
        next_reminders = 0
        while True:
            try:
                if time.monotonic() >= next_reminders:
                    db.rpc('encolar_recordatorios_instancias', {}).execute()
                    next_reminders = time.monotonic() + 60
                worked = process_one(db, settings, client)
            except Exception:
                print("No se pudo completar el ciclo de correo. Revisar estado de la cola; no se muestran datos privados.", flush=True)
                worked = False
            count += 1
            if args.once and (not worked or count >= 100):
                break
            if not worked:
                time.sleep(15)


if __name__ == "__main__":
    main()
