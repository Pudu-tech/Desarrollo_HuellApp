"""Diseño email de HuellApp: tarjeta blanca, teal/coral y logo como recuperación.

Tablas y estilos inline para clientes de correo. Escapa todos los datos y URLs.
"""
from html import escape


DEFAULT_EMAIL_LOGO_URL = 'https://blmqcxxussubgzvtendl.supabase.co/storage/v1/object/public/huellapp-email-assets/logo-huella-55ebe75ae253eec1.png'


def render_invitation_email(frontend_url, title, fields, accept_url, reject_url, logo_url=None):
    rows=''.join(f'<tr><td width="35%" valign="top" style="padding:8px 0;color:#245f6b;font-size:13px">{escape(str(label))}</td>'
                f'<td style="padding:8px 0 8px 16px;color:#111111;font-size:14px">{escape(str(value))}</td></tr>'
                for label,value in fields if value)
    logo=escape(logo_url or DEFAULT_EMAIL_LOGO_URL,quote=True)
    return f'''<!doctype html><html lang="es"><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0;padding:12px;background:#f4f6f7;font-family:Arial,sans-serif">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center">
    <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #dbe3e6;border-radius:18px">
      <tr><td align="center" style="padding:24px 20px 12px"><img src="{logo}" width="112" alt="Fundación Huella" style="display:block;margin:0 auto 12px;width:112px;height:auto;border:0;background:#ffffff">
      <p style="color:#245f6b;font-size:22px;font-weight:bold;margin:12px 0">HuellApp</p></td></tr>
      <tr><td style="padding:0 20px 24px"><h1 style="text-align:center;color:#111111;font-size:24px;margin:0 0 14px">{escape(title)}</h1>
      <p style="text-align:center;color:#66717a;line-height:1.6">Revisa los datos de la actividad y confirma tu participación.</p>
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="background:#f58a5b;border-radius:8px;padding:15px">
      <a href="{escape(accept_url,quote=True)}" style="color:#ffffff;font-weight:bold;text-decoration:none;display:block">Aceptar participación</a></td></tr></table>
      <p style="text-align:center;margin:20px 0"><a href="{escape(reject_url,quote=True)}" style="color:#245f6b;font-weight:bold">Rechazar participación</a></p>
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0">{rows}</table>
      <p style="color:#66717a;line-height:1.6">Tu respuesta se comparte con HuellApp. Si la actividad cambió, deberás responder esta nueva invitación.</p>
      <div style="background:#edf8f6;border:1px solid #b9ded8;border-radius:8px;padding:14px;color:#246b65;font-size:13px;line-height:1.6">Los botones abren una confirmación. Aceptar confirma tu participación; la asistencia se registra por separado.</div>
      <p style="text-align:center;font-size:13px;margin:24px 0 0"><a href="{escape(frontend_url,quote=True)}" style="color:#245f6b">Ingresar a HuellApp</a></p>
      </td></tr></table></td></tr></table></body></html>'''
