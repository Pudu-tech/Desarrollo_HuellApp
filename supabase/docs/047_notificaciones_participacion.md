# Invitaciones por correo y respuesta compartida (047)

## Aplicación

1. Aplicar `supabase/migrations/047_notificaciones_participacion.sql` después de
   046 en DEV/QA. No aplicar otra vez una migración ya confirmada.
2. Ejecutar `supabase/tests/047_notificaciones_participacion.sql`. Requiere
   SUPERADMIN y un MONITOR/COORDINADOR/DIRECTIVA activo con permisos de aceptar
   y rechazar; maestros CAPACITACION, RELATOR y estados PENDIENTE. No manda
   correos y revierte todo con ROLLBACK.
3. Desplegar API y frontend juntos. Configurar las variables privadas del backend
   usando `backend/.env.example` como referencia.

```dotenv
BREVO_NOTIFICATIONS_ENABLED=true
BREVO_API_KEY=<clave privada de API de Brevo>
BREVO_SENDER_EMAIL=<remitente verificado en Brevo>
BREVO_SENDER_NAME=HuellApp
NOTIFICATION_TOKEN_SECRET=<secreto aleatorio independiente de al menos 32 caracteres>
FRONTEND_URL=https://<frontend del ambiente>
```

La clave de API no es la contraseña SMTP de Supabase. No copiar secretos a
React, VITE_*, SQL, chats, repositorio ni logs. El remitente debe existir en
Brevo. El valor por defecto mantiene el envío deshabilitado, pero las nuevas
invitaciones se siguen guardando. No se generan correos de asignaciones
anteriores a la migración.

4. Ejecutar un worker separado del servidor HTTP, desde `backend`:

```powershell
python -m app.workers.notifications
```

Para procesar hasta 100 pendientes y terminar:

```powershell
python -m app.workers.notifications --once
```

En producción configurar ese comando como proceso supervisado que se reinicie
al caer. Arrancar FastAPI únicamente no procesa la cola. Varios workers pueden
trabajar con reservas excluyentes. No usar BackgroundTasks como garantía de
entrega: la cola vive en PostgreSQL y sobrevive al reinicio de la API.

## Qué queda implementado

- Cada nueva participación pendiente genera una notificación interna y una
  entrega EMAIL en la misma transacción que crea la asignación. Fallar la
  notificación revierte la operación; fallar Brevo después no borra la asignación.
- Monitor, coordinador y directiva tienen un listado personal real y pueden
  responder desde HuellApp. Las rutas personales consultan solo participaciones
  del usuario autenticado; no exponen correos ni participantes de terceros.
- El correo incluye tipo de actividad, fecha/horario, colegio/lugar, curso, sala,
  asignatura/espacio y tipo de participación. HTML escapa los datos de catálogo.
- Aceptar/Rechazar abre `/responder-participacion` y exige confirmación. No
  requiere iniciar sesión: el enlace personal firmado funciona como credencial
  limitada. No reenviarlo a terceros. Abrirlo/consultarlo no altera el estado.
- Los tokens usan HS256, audiencia/emisor restringidos y una versión de la
  invitación; vencen a los siete días o al finalizar la actividad, lo que ocurra
  primero. Se transportan en fragmento de URL, luego en cuerpos POST; la página
  retira el fragmento de la barra/historial y no lo persiste en almacenamiento.
  Para volver a consultar tras recargar, abrir nuevamente el enlace del correo.
- Reprogramación, cambio de contexto, reactivación, reasignación y reapertura
  invalidan versiones anteriores. Las participaciones pendientes generan una
  invitación nueva. Modificar una observación o aceptar otro participante no
  renueva la invitación. No reabre respuestas aceptadas por sí solo.
- WEB y EMAIL escriben el mismo registro y bloquean asignación/participación en
  el mismo orden. La primera respuesta válida se conserva; la siguiente devuelve
  el estado existente sin cambiarlo, incluso si intenta la acción contraria.
- Se reutilizan permisos ACCEPT_PARTICIPATION/REJECT_PARTICIPATION, RPC auditadas
  existentes y confirmación automática cuando acepta un RELATOR. Se añade un
  evento PARTICIPATION_RESPONSE_CHANNEL con canal real. Las auditorías de dominio
  originales se conservan; el nuevo evento identifica el origen de la respuesta.
- El detalle personal refresca al recuperar foco y cada 30 segundos. Al responder
  obtiene el estado confirmado de inmediato. La sincronización no usa WebSocket.
- WhatsApp no envía nada y su canal todavía no admite respuestas. Se implementará
  al final sobre el mismo estado, con autenticación/verificación de webhook.

## Seguimiento y reintentos

La cola usa PENDIENTE, PROCESANDO, ENVIADA, FALLIDA, INCIERTA y CANCELADA.
`notificacion_intentos` conserva un registro por reserva/intentado, incluso
después de un reintento manual. Una invitación respondida, expirada o invalidada
se cancela antes de enviarse cuando el worker la detecta. Puede haber un correo
en tránsito mientras se responde/cancela; su enlace vuelve a validar el estado.

ENVIADA significa que Brevo aceptó la solicitud; no certifica recepción en el
buzón. Los webhooks de entregado/rebotado todavía no están implementados.
El envío usa la [API transaccional de Brevo](https://developers.brevo.com/docs/send-a-transactional-email)
y una clave UUID de [idempotencia](https://developers.brevo.com/docs/heterogenous-versions-batch-emails).
Brevo limita esa deduplicación a 30 minutos; no garantiza entrega exactamente
una vez para siempre. Por eso un timeout, HTTP 5xx o worker caído queda INCIERTA,
sin reenvío automático. HTTP 429 se reintenta con espera creciente, hasta cinco
intentos. Un rechazo definitivo queda FALLIDA.

SUPERADMIN recibe VIEW_NOTIFICATION_DELIVERY y RETRY_NOTIFICATION_DELIVERY.
Los endpoints permiten consultar estados/intentos sin mostrar tokens:

- GET `/notificaciones/envios`: últimos 100 envíos.
- POST `/notificaciones/envios/{id}/reintentar`, cuerpo
  `{"entrega_verificada": false}` para un fallo definitivo, después de corregir
  configuración o destinatario. El contador del ciclo se reinicia; su historial
  de intentos permanece.
- Para INCIERTA comprobar primero en Brevo que el mensaje no fue aceptado/enviado;
  solo entonces indicar `{"entrega_verificada": true}`. La acción queda auditada.
  ENVIADA/PROCESANDO/CANCELADA no admiten este reintento.

## Validación manual

1. Crear una asignación futura con monitor/coordinador/directiva; comprobar
   notificación y EMAIL PENDIENTE por participante. Arrancar el worker y recibir
   los correos en DEV/QA con destinatarios de prueba.
2. Abrir Aceptar sin confirmar: debe seguir PENDIENTE. Confirmar y revisar el
   estado propio en HuellApp. Desde Rechazar del mismo correo debe mostrar
   que ya aceptó, sin cambiarlo. Probar también en orden contrario.
3. Probar rechazo con motivo; conservarlo y no permitir una aceptación posterior.
4. Reabrir/reprogramar: enlace anterior debe indicar invitación reemplazada;
   comprobar nueva versión y correo pendiente para las participaciones pendientes.
5. Cancelar la asignación: no admitir respuesta ni enviar invitación pendiente.
6. Correo de otro usuario no debe modificar la participación del usuario con sesión:
   el enlace responde solo por su destinatario; la ruta WEB exige dueño real.
7. Probar dos respuestas simultáneas con dos sesiones/canales. Una sola transición
   y un solo evento PARTICIPATION_RESPONSE_CHANNEL; ambos ven el estado final.
8. Revisar cola, intentos y auditoría. Nunca mostrar tokens en capturas/logs.

El test SQL verifica rollback de auditoría, duplicados, permisos, vencimiento,
versiones, reserva exclusiva y reintento explícito. Las pruebas Python preparadas
simulan Brevo y tokens; las pruebas frontend simulan HTTP y no envían correos.

## Asistencia pendiente

Aceptar/rechazar registra la decisión de participar. La asistencia existente
permanece PENDIENTE después de aceptar; el test SQL lo verifica explícitamente.
Ya existen tablas, triggers y endpoints de asistencia propia/regularización en
el backend. Falta implementar la interfaz, conectar geolocalización y verificar
sus reglas con pruebas integrales. Ese trabajo debe realizarse después de este
flujo de invitación y antes de cerrar el módulo. WhatsApp queda para el final.
