# Eliminación de asignaciones

Ejecutar migración 051 y prueba 051 después de 050. La prueba revierte sus fixtures
y no envía correo. Requiere usuarios activos SUPERADMIN, DIRECTIVA y COORDINADOR.

En Ver detalle aparece Eliminar asignación para SUPERADMIN y DIRECTIVA con DELETE_ASSIGNMENT.
La API y la RPC verifican tanto permiso como rol, incluso ante una concesión
accidental del permiso a COORDINADOR. El diálogo confirma actividad, fecha y hora.

La operación marca activo=false y deleted_at, registra DELETE_ASSIGNMENT y cancela
correos pendientes, dentro de la misma transacción. Una falla de auditoría revierte
todo. Participantes, respuestas, asistencias e historial se conservan. Las consultas
operativas y los enlaces de respuesta excluyen asignaciones eliminadas.

Los correos ya enviados o en tránsito no se pueden retirar del buzón, pero sus
enlaces no permiten responder a una asignación eliminada. Esta función limpia los
listados, sin purgar físicamente los registros históricos de la base de datos.
