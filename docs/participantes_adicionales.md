# Participantes adicionales y asignaciones eliminadas

En **Asignaciones → Ver detalle → Agregar participante**, SUPERADMIN, DIRECTIVA y COORDINADOR pueden incorporar personas a actividades pendientes o confirmadas. Se puede repetir la operación sin un límite de participantes, excluyendo personas que ya tienen una participación activa. Se conservan las respuestas anteriores; cada nuevo participante recibe su propia invitación y asistencia pendiente, mediante la RPC existente `agregar_participante_atomico` y los triggers de notificaciones.

Las asignaciones eliminadas lógicamente no aparecen en las consultas de participaciones propias. El panel consulta sin caché al abrirse, al recuperar el foco y cada 15 segundos mientras está visible. La desaparición en otro navegador depende de la siguiente consulta y de la conexión. La auditoría y el historial permanecen conservados.

Esta mejora no requiere una nueva migración: utiliza las funciones existentes de 025, 047 y 051, y los permisos de gestión de 049/050.

Cada fila del detalle permite **Cambiar participante** o **Quitar participante**, también si todavía no respondió o si aceptó. Ambas acciones requieren confirmación y permiso `REASSIGN_ASSIGNMENT`, y utilizan las RPC auditadas de 019 y 023. El reemplazo conserva el tipo de participación y recibe una invitación nueva; la participación anterior se archiva. Quitar no elimina físicamente la asistencia ni el historial. Si se retira o reemplaza al último relator aceptado de una actividad confirmada, las funciones existentes la devuelven a pendiente.
