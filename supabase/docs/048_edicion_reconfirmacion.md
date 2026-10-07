# Edición y reconfirmación (048)

Aplicar `supabase/migrations/048_edicion_reconfirmacion_asignacion.sql` después
de 047; luego ejecutar `supabase/tests/048_edicion_reconfirmacion_asignacion.sql`
en DEV/QA. El test no envía correos y usa ROLLBACK. No reaplicar una migración
confirmada: 048 renombra la RPC 029 para reutilizar su validación y snapshots.

En **Asignaciones → Ver detalle → Editar asignación**, UPDATE_ASSIGNMENT permite
editar los campos de la actividad. Los catálogos de edición exigen ese permiso
y no requieren CREATE_ASSIGNMENT. Tipo de actividad y participantes permanecen
fijos; su gestión pertenece a otro flujo. Se envían solo los campos modificados
mediante PATCH, conservando semántica de null y control de concurrencia existente.

Cambiar fecha, horario, colegio/lugar, curso, sala, asignatura o espacio reinicia
las participaciones activas a PENDIENTE y limpia la respuesta actual. Conserva
la respuesta anterior en audit_logs, regenera una versión por participante y
encola una única invitación nueva. La asignación CONFIRMADA vuelve a PENDIENTE;
aceptar de nuevo como RELATOR la confirma usando las reglas existentes.

Cambiar observaciones, contactos o reenviar un valor idéntico no pide otra
respuesta. Actividades cerradas/históricas o con asistencia ya informada no
permiten reprogramar sus condiciones. La asistencia se conserva y no se registra
al aceptar. Si falla una auditoría, todo el cambio y las notificaciones nuevas
se revierten. Los enlaces anteriores no pueden responder la nueva versión.

El correo nuevo dice **Asignación actualizada en HuellApp** y tiene la tarjeta
blanca, logo, teal y coral de recuperación de contraseña. La página pública usa
`auth-pages.css` junto con estilos específicos de invitación. El correo usa
tablas y estilos inline. El logo apunta al FRONTEND_URL configurado; debe ser
una URL pública para que clientes de correo remotos lo carguen. En localhost,
algunos clientes lo bloquean; el nombre HuellApp sigue visible.

Tras aplicar 048, reiniciar API y worker. Las invitaciones nuevas usan la nueva
plantilla; un correo enviado previamente no cambia. Ejecutar el worker habitual
para procesar los nuevos pendientes (o mantenerlo en ejecución sin --once).

Prueba manual: aceptar una asignación futura, editar su fecha/horario y guardar;
comprobar estado PENDIENTE, recibir correo actualizado y responderlo. El correo
anterior debe indicar invitación reemplazada. Editar solo observaciones después
de aceptar debe conservar la respuesta y no crear un correo adicional.

La asistencia continúa pendiente como implementación de interfaz. WhatsApp
sigue para el final; la reconfirmación usa el estado compartido de participación.
