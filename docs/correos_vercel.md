# Correos con Vercel Hobby y Supabase

No se agregan proveedores: el webhook asíncrono de Supabase invoca la API en
Vercel y esta ejecuta el worker existente durante la petición HTTP. La cola
permanece en PostgreSQL. No se usa un proceso infinito ni tareas que deban
sobrevivir después de responder la petición.

## Despliegue del backend

El proyecto `huellapp-backend` debe usar Root Directory `backend`, con el
entrypoint FastAPI `app/main.py`. El archivo `backend/vercel.json` configura
300 segundos de duración máxima y un cron diario compatible con Hobby.
No copiar esta configuración al proyecto frontend.

1. Desplegar estos cambios desde `develop` al backend.
2. Conservar las variables privadas existentes de Supabase, Brevo y firma.
   `BREVO_NOTIFICATIONS_ENABLED=true` y `FRONTEND_URL` debe ser la URL del
   frontend DEV. No usar variables `VITE_*` para secretos.
3. Generar **dos secretos diferentes**, aleatorios de al menos 32 caracteres,
   y guardarlos solo en las variables del backend de Vercel:
   `NOTIFICATION_WEBHOOK_SECRET` y `CRON_SECRET`. No reutilizar el secreto de
   firma de invitaciones ni subir `.env`. Volver a desplegar para cargarlos.
4. Copiar la URL pública HTTPS del backend desde Vercel. El enlace
   `vercel.com/huell-app/huellapp-backend` es el panel, no la URL de la API.
   Usar un dominio estable del ambiente, no un deployment temporal.

## Webhook de Supabase: envío al crear una invitación

En el proyecto Supabase **DEV**, Database > Webhooks, crear:

| Campo | Valor |
| --- | --- |
| Nombre | `huellapp_email_insert_dev` |
| Tabla | `public.notificacion_envios` |
| Evento | **INSERT solamente** |
| Método | POST |
| URL | `https://<backend-dev>/internal/notifications/webhook` |
| Header | `Authorization: Bearer <NOTIFICATION_WEBHOOK_SECRET>` |
| Header | `Content-Type: application/json` |
| Timeout | 120000 ms, si el panel permite configurarlo |

No seleccionar UPDATE: el propio worker actualiza los envíos y produciría
invocaciones recursivas. El cuerpo del webhook no determina destinatarios ni
contenido. Cada aviso intenta tomar un pendiente de la cola usando la reserva
exclusiva existente, que también coordina invocaciones simultáneas y el worker
local. Las entregas ya procesadas no vuelven a reservarse.

Si Vercel protege el deployment, configurar la excepción de acceso adecuada
o añadir el header `x-vercel-protection-bypass` con el secreto de automatización
del proyecto, si está disponible. Mantener la autenticación propia del endpoint.
Un 401 o una página de login de Vercel significa que el webhook no llegó a la API.

## Recuperación y límites

`GET /internal/notifications/cron` requiere `Authorization: Bearer <CRON_SECRET>`.
Vercel agrega ese header a sus cron jobs automáticamente. El cron solicita una
ejecución diaria a las 08:17 UTC y **solo corre en Production, no en Preview**.
Si el backend DEV es Production de su propio proyecto, sí puede usarlo. Si es
Preview, el webhook sigue funcionando, pero hay que invocar el endpoint de
recuperación de forma manual o programarlo dentro del Supabase existente.

Cada recuperación procesa como máximo 100 trabajos e impide comenzar nuevos
después de 180 segundos. Un trabajo ya iniciado termina normalmente; el plazo
no interrumpe una llamada a Brevo. `procesadas` incluye cancelaciones y no
significa correos entregados al buzón.

El webhook es un aviso, no una garantía de entrega. Si se pierde o encuentra
la API caída, el correo sigue pendiente hasta una recuperación. Los rechazos
429 se reprograman en la cola existente y se recogen en una ejecución posterior;
no se promete reintento inmediato con el cron diario. Un timeout de red puede
dejar un envío INCIERTA: verificar Brevo antes de reintentarlo. Para más de 100
pendientes se necesitan más invocaciones de recuperación.

En Supabase se pueden revisar las respuestas HTTP del webhook en el esquema
`net`; en Vercel, los logs de la función; en HuellApp, los estados de envíos.
Un 200 del endpoint significa que el ciclo terminó: el estado individual puede
ser ENVIADA, CANCELADA, FALLIDA, PENDIENTE o INCIERTA.

## Prueba de aceptación

1. Cerrar el worker local para comprobar independencia de la PC.
2. Crear desde el frontend DEV una asignación futura con un participante de prueba.
3. Confirmar que quedó guardada, que el webhook recibió 200 y que llegó el correo.
4. Abrir el enlace de respuesta y verificar que apunta al frontend DEV.
5. Repetir con varios participantes. Verificar una entrega por invitación en Brevo.
6. Probar la ruta sin Authorization: debe responder 401 sin procesar la cola.

No activar webhooks de DEV y producción contra un mismo proyecto Supabase:
ambos competirían por la misma cola y podrían generar enlaces de otro ambiente.
Para revertir, desactivar el webhook y el cron; se puede volver al worker CLI.

Referencias oficiales:
- https://supabase.com/docs/guides/database/webhooks
- https://vercel.com/docs/frameworks/backend/fastapi
- https://vercel.com/docs/cron-jobs/manage-cron-jobs
- https://vercel.com/docs/cron-jobs/usage-and-pricing
