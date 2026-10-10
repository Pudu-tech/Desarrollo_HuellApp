"""Invitaciones personales: firma de enlaces y vista mínima del destinatario.

El token autoriza únicamente la respuesta a una versión de participación.
No se registra en logs, se usa en cuerpos HTTP y se transporta como fragmento.
"""
from datetime import datetime, timezone
from uuid import UUID
import jwt
from fastapi import HTTPException
from app.core.config import get_settings


def signing_secret() -> str:
    value = get_settings().notification_token_secret
    secret = value.get_secret_value() if value else ""
    if len(secret) < 32:
        raise RuntimeError("Configura NOTIFICATION_TOKEN_SECRET con al menos 32 caracteres.")
    return secret


def invitation_token(notification: dict) -> str:
    expires = datetime.fromisoformat(notification["expires_at"].replace("Z", "+00:00"))
    return jwt.encode({"iss": "huellapp-invitations", "aud": "participation-response",
                       "sub": notification["usuario_destino_id"], "nid": notification["id"],
                       "pid": notification["participacion_id"], "version": notification["invitacion_version"],
                       "exp": int(expires.timestamp())}, signing_secret(), algorithm="HS256")


def verify_invitation(db, token: str) -> dict:
    try:
        secret = signing_secret()
    except RuntimeError as exc:
        raise HTTPException(503, "El backend no tiene cargado el secreto de las invitaciones. Revisa NOTIFICATION_TOKEN_SECRET y reinicia el backend.") from exc
    try:
        claims = jwt.decode(token, secret, algorithms=["HS256"], audience="participation-response",
                            issuer="huellapp-invitations", options={"require": ["exp", "sub", "nid", "pid", "version"]})
        for key in ("sub", "nid", "pid", "version"):
            UUID(claims[key])
    except (jwt.PyJWTError, ValueError, TypeError) as exc:
        raise HTTPException(410, "El enlace no es válido o venció. Consulta tu participación en HuellApp.") from exc
    rows = db.table("notificaciones").select("*").eq("id", claims["nid"]).eq("usuario_destino_id", claims["sub"]).execute().data or []
    if not rows:
        raise HTTPException(410, "La invitación ya no está disponible.")
    row = rows[0]
    if (row["participacion_id"] != claims["pid"] or row["invitacion_version"] != claims["version"]
        or not row["activo"] or datetime.fromisoformat(row["expires_at"].replace("Z", "+00:00")) <= datetime.now(timezone.utc)):
        raise HTTPException(410, "La invitación venció o fue reemplazada.")
    return row


def personal_summary(db, assignment_id: str, actor_id: str, version: str | None = None) -> dict:
    """Solo consulta la participación propia, sin revelar correos de terceros."""
    rows = db.table("asignacion_participantes").select("id,usuario_id,created_at,notificaciones(invitacion_version,created_at),asistencia:asistencias_asignacion(estado),invitacion_version,estado_participacion_id,estados_participacion(codigo),tipos_participacion(nombre),motivo_rechazo,fecha_respuesta") \
        .eq("asignacion_id", assignment_id).eq("usuario_id", actor_id).eq("activo", True).is_("deleted_at", "null").execute().data or []
    if not rows:
        raise HTTPException(404, "No tienes una participación disponible en esta asignación.")
    part = rows[0]
    if version is not None and part["invitacion_version"] != version:
        raise HTTPException(410, "La asignación cambió. Utiliza la invitación más reciente.")
    rows = db.table("asignaciones").select("id,fecha,hora_inicio,hora_fin,lugar,observacion,activo,tipo_actividad_id,tipos_actividad(nombre),colegios(nombre),cursos_colegio(nombre_mostrado),salas(nombre),ramos(nombre),espacios_reflexion(nombre),espacios_encuentro(nombre),estados_asignacion(codigo)") \
        .eq("id", assignment_id).is_("deleted_at", "null").execute().data or []
    if not rows:
        raise HTTPException(404, "La asignación no está disponible.")
    return project_personal_summary(part, rows[0], assignment_id)


def project_personal_summary(part: dict, assignment: dict, assignment_id: str) -> dict:
    """Proyección compartida de lectura propia, sin nuevas consultas."""
    def name(key, field="nombre"):
        return (assignment.get(key) or {}).get(field)
    invitations = part.get("notificaciones") or []
    current_dates = [n["created_at"] for n in invitations
                     if n.get("invitacion_version") == part["invitacion_version"] and n.get("created_at")]
    received = part.get("created_at")
    latest = max(current_dates, default=received)
    updated = latest if len(invitations) > 1 and current_dates else None
    attendance = part.get('asistencia') or []
    if isinstance(attendance, list):
        attendance = attendance[0] if attendance else {}
    return {"asignacion_id": assignment_id, "participante_id": part["id"], "invitacion_version": part["invitacion_version"], "estado": part["estados_participacion"]["codigo"],
            "recibida_at": received, "actualizada_at": updated, "ultima_invitacion_at": latest,
            "asistencia_estado": attendance.get('estado'),
            "fecha_respuesta": part.get("fecha_respuesta"), "motivo_rechazo": part.get("motivo_rechazo"),
            "actividad": name("tipos_actividad"), "fecha": assignment["fecha"], "hora_inicio": assignment["hora_inicio"],
            "hora_fin": assignment["hora_fin"], "colegio": name("colegios"), "curso": name("cursos_colegio", "nombre_mostrado"),
            "sala": name("salas"), "asignatura": name("ramos"), "lugar": assignment["lugar"], "observacion": assignment["observacion"],
            "espacio": name("espacios_reflexion") or name("espacios_encuentro"), "tipo_participacion": (part.get("tipos_participacion") or {}).get("nombre"),
            "admite_respuesta": assignment["activo"] and assignment["estados_asignacion"]["codigo"] in ("PENDIENTE", "CONFIRMADA")
                and part["estados_participacion"]["codigo"] == "PENDIENTE"}


def personal_summaries(db, actor_id: str) -> list[dict]:
    """Una consulta de relaciones; no realiza dos consultas por actividad."""
    rows = db.table("asignacion_participantes").select(
        "id,usuario_id,created_at,notificaciones(invitacion_version,created_at),asistencia:asistencias_asignacion(estado),invitacion_version,asignacion_id,estados_participacion(codigo),tipos_participacion(nombre),motivo_rechazo,fecha_respuesta,"
        "asignacion:asignaciones!inner(id,fecha,hora_inicio,hora_fin,lugar,observacion,activo,deleted_at,tipos_actividad(nombre),"
        "colegios(nombre),cursos_colegio(nombre_mostrado),salas(nombre),ramos(nombre),espacios_reflexion(nombre),"
        "espacios_encuentro(nombre),estados_asignacion(codigo))"
    ).eq("usuario_id", actor_id).eq("activo", True).is_("deleted_at", "null").is_("asignacion.deleted_at", "null").execute().data or []
    return sorted([project_personal_summary(part, part["asignacion"], part["asignacion_id"])
                   for part in rows if part.get("asignacion") and not part["asignacion"].get("deleted_at")],
                  key=lambda item: (item["ultima_invitacion_at"] or "", item["participante_id"]), reverse=True)
