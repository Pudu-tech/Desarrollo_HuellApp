"""Lectura propia y confirmación explícita desde WEB o un enlace personal EMAIL.

Consultar un enlace nunca altera el estado. El RPC serializa respuestas simultáneas.
"""
from typing import Literal
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from app.core.security import get_current_user, require_permission
from app.core.supabase import get_supabase_client
from app.schemas.auth import AuthenticatedUser
from app.api.salas import _request_rpc_context
from app.services.participation_notifications import personal_summary, personal_summaries, verify_invitation

router = APIRouter(tags=["Invitaciones y participación propia"])


class InvitationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    token: str = Field(min_length=20, max_length=2048)


class ParticipationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    accion: Literal["ACCEPT", "REJECT"]
    motivo: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def rejection_reason(self):
        if self.accion == "REJECT" and not self.motivo:
            raise ValueError("Indica el motivo del rechazo.")
        return self


class InvitationResponse(ParticipationResponse, InvitationRequest):
    pass


def respond(db, request, assignment_id, participant_id, actor_id, datos, canal, version=None):
    context = _request_rpc_context(request)
    result = db.rpc("responder_participacion_canal_atomica", {
        "p_asignacion_id": str(assignment_id), "p_participante_id": str(participant_id),
        "p_actor_user_id": str(actor_id), "p_accion": datos.accion, "p_canal": canal,
        "p_version": version, "p_motivo": datos.motivo,
        **{f"p_{key}": value for key, value in context.items()},
    }).execute().data
    if not isinstance(result, dict):
        raise RuntimeError("Respuesta RPC inválida")
    if result.get("ok") is not True:
        code = result.get("error_code")
        if code in ("FORBIDDEN", "ACTOR_NOT_FOUND", "NOT_PARTICIPANT_OWNER"):
            raise HTTPException(403, "No puedes responder esta participación.")
        if code == "INVITATION_EXPIRED":
            raise HTTPException(410, "La invitación venció o cambió.")
        if code == "INVALID_REJECTION_REASON":
            raise HTTPException(422, "Indica el motivo del rechazo.")
        raise HTTPException(409, "La asignación o participación ya no admite esta respuesta. Actualiza su estado.")
    return {"estado": result["estado"], "ya_respondida": result.get("ya_respondida", False)}


@router.get("/mi-participacion")
def my_assignments(actor: AuthenticatedUser = Depends(get_current_user)):
    return personal_summaries(get_supabase_client(), str(actor.id))


@router.get("/mi-participacion/{asignacion_id}")
def my_participation(asignacion_id: UUID, actor: AuthenticatedUser = Depends(get_current_user)):
    return personal_summary(get_supabase_client(), str(asignacion_id), str(actor.id))


@router.post("/mi-participacion/{asignacion_id}/responder")
def web_response(asignacion_id: UUID, datos: ParticipationResponse, request: Request,
                       actor: AuthenticatedUser = Depends(get_current_user)):
    db = get_supabase_client()
    own = personal_summary(db, str(asignacion_id), str(actor.id))
    return respond(db, request, asignacion_id, own["participante_id"], actor.id, datos, "WEB")


@router.post("/invitaciones/consultar")
def invitation_preview(datos: InvitationRequest):
    db = get_supabase_client()
    invitation = verify_invitation(db, datos.token)
    return personal_summary(db, invitation["entidad_id"], invitation["usuario_destino_id"], invitation["invitacion_version"])


@router.post("/invitaciones/responder")
def email_response(datos: InvitationResponse, request: Request):
    db = get_supabase_client()
    invitation = verify_invitation(db, datos.token)
    return respond(db, request, invitation["entidad_id"], invitation["participacion_id"], invitation["usuario_destino_id"],
                   datos, "EMAIL", invitation["invitacion_version"])


@router.get("/notificaciones/envios")
def delivery_status(_actor: AuthenticatedUser = Depends(require_permission("VIEW_NOTIFICATION_DELIVERY"))):
    """Seguimiento técnico mínimo, sin tokens ni correos de destinatarios."""
    return get_supabase_client().table("notificacion_envios").select(
        "id,notificacion_id,estado,intentos,fecha_intento,fecha_envio,error_mensaje,identificador_externo,notificacion_intentos(id,iniciado_at,finalizado_at,estado,error_mensaje)") \
        .eq("proveedor", "BREVO_ASIGNACIONES").order("created_at", desc=True).limit(100).execute().data or []


class DeliveryRetry(BaseModel):
    model_config = ConfigDict(extra="forbid")
    entrega_verificada: bool = False


@router.post("/notificaciones/envios/{envio_id}/reintentar")
def retry_delivery(envio_id: UUID, datos: DeliveryRetry, request: Request,
                         actor: AuthenticatedUser = Depends(require_permission("RETRY_NOTIFICATION_DELIVERY"))):
    context = _request_rpc_context(request)
    result = get_supabase_client().rpc("reintentar_envio_participacion", {
        "p_id": str(envio_id), "p_actor": str(actor.id), "p_verificado": datos.entrega_verificada,
        **{f"p_{key}": value for key, value in context.items()},
    }).execute().data
    if not isinstance(result, dict):
        raise HTTPException(500, "No fue posible reintentar el envío.")
    if result.get("ok") is not True:
        if result.get("error_code") == "FORBIDDEN":
            raise HTTPException(403, "No tienes permiso para reintentar envíos.")
        if result.get("error_code") == "NOT_FOUND":
            raise HTTPException(404, "Envío no encontrado.")
        raise HTTPException(409, "El envío no admite reintento. Para una entrega incierta, verifica primero en Brevo que no fue enviada.")
    return {"ok": True}
