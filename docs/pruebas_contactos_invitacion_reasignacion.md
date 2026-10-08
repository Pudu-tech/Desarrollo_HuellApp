# Contactos, acceso de usuarios y reasignación

Aplicar migración 052 y prueba 052 en Supabase para retirar el máximo de dos
contactos. Permanece el mínimo de uno para actividades escolares, la pertenencia
al colegio y la prohibición de duplicar contactos. No hay máximo de cantidad en
formulario, Pydantic ni trigger. No es una garantía de recursos ilimitados del servidor.

Usuarios > Editar > Acceso y contraseña > Enviar nueva invitación: SUPERADMIN y
DIRECTIVA pueden solicitar un enlace de recuperación para una cuenta activa.
Se usa el email actual del perfil, nunca un email recibido del navegador. DIRECTIVA
no puede recuperar cuentas SUPERADMIN. El permiso requerido es UPDATE_USER, además
del rol administrativo. Se audita la solicitud antes de contactar Supabase Auth.
Un fallo posterior del proveedor deja registrada la solicitud, sin afirmar entrega.
Se usa `/restablecer-password`, que debe estar autorizado en las Redirect URLs de
Supabase Auth. Se conserva el flujo SMTP de Supabase ya configurado para recuperar
contraseñas; no es un correo de la cola de invitaciones a actividades.

Asignaciones > Ver detalle > Participantes y respuestas > Reasignar a otro monitor:
visible en participaciones RECHAZADAS de actividades abiertas, bajo
REASSIGN_ASSIGNMENT. SUPERADMIN, DIRECTIVA y COORDINADOR reciben ese permiso.
El catálogo de reasignación solo expone nombres e IDs de MONITOR activos; se
excluyen quienes ya participan en la actividad. La RPC existente 019 archiva la
participación anterior, preserva el motivo y la asistencia, y crea una participación
nueva. Los triggers 047 generan su versión e invitación EMAIL. No se reenvía la
respuesta del monitor anterior ni se reemplaza su identidad histórica.

Para correo con logo, el render actual usa el PNG público de Fundación Huella y
requiere reiniciar el worker para cargar código nuevo. Una comprobación de la imagen
del último correo en Brevo respondió HTTP 200, image/png. El correo de las 18:40
mostrado en la captura es anterior; los mensajes ya enviados no se reescriben.
Los clientes pueden bloquear imágenes externas: habilitarlas para ese remitente.

La configuración local del correo fue actualizada posteriormente para usar una
copia idéntica de `frontend/public/logo-huella.png` en Supabase Storage, bucket público
`huellapp-email-assets`. El nombre incluye el hash del archivo y la URL no contiene
parámetros, autenticación ni enlaces temporales. Se verificó HTTP 200, image/png y
SHA256 idéntico al archivo local. Solo el logo público se publicó, sin datos de usuarios.
La URL se configura en BREVO_EMAIL_LOGO_URL dentro de backend/.env; para otro entorno
configurar esa variable con el asset público correspondiente. El worker local fue
reiniciado comprobando que no hubiera envíos PROCESANDO. No se cambian correos anteriores
ni se envía una invitación de prueba automáticamente.

Probar contactos con tres o más personas; solicitar recuperación desde ambos roles;
rechazar una invitación, reasignarla y aceptar el correo del nuevo monitor. Las
pruebas locales no envían correos reales; la comprobación de extremo a extremo queda
para DEV/QA. La prueba SQL revierte todos sus fixtures.
