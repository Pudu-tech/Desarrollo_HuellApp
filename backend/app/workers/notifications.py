"""Worker Brevo: python -m app.workers.notifications [--once].

Reserva duradera y excluyente; no envía si falta configuración. Una caída o
timeout ambiguo queda INCIERTA y exige verificar Brevo antes de reenviar.
ENVIADA significa aceptada por Brevo, no confirmación de entrega al buzón.
"""
import argparse
import time
from urllib.parse import urlencode, urlparse
import httpx
from app.core.config import get_settings
from app.core.supabase import get_supabase_client
from app.services.participation_notifications import invitation_token, personal_summary, signing_secret
from fastapi import HTTPException
from app.services.invitation_email import render_invitation_email


def check_configuration(settings):
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
    title = notification.get('titulo') or 'Nueva asignación en HuellApp'
    content = render_invitation_email(settings.normalized_frontend_url, title, fields, accept, reject)
    text = '\n'.join(f'{label}: {value}' for label, value in fields if value)
    return {"sender": {"name": settings.brevo_sender_name, "email": settings.brevo_sender_email},
            "to": [{"email": recipient["email"], "name": recipient["nombres"]}],
            "subject": title, "htmlContent": content,
            "textContent": f'HuellApp\n{text}\nAceptar: {accept}\nRechazar: {reject}\nAceptar no registra asistencia.',
            "headers": {"idempotencyKey": delivery_id}}


def process_one(db, settings, client):
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
        if not own["admite_respuesta"]:
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


def main():
    parser = argparse.ArgumentParser(description="Cola de invitaciones por Brevo")
    parser.add_argument("--once", action="store_true", help="Procesa hasta 100 pendientes y termina")
    args = parser.parse_args()
    settings = get_settings()
    check_configuration(settings)  # No reserva filas si no está listo el canal.
    db = get_supabase_client()
    with httpx.Client(timeout=30) as client:
        count = 0
        while True:
            try:
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
