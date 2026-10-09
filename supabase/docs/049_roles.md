# Roles de HuellApp

Aplicar `supabase/migrations/049_alineacion_permisos_roles.sql` después de 048.
Luego ejecutar `supabase/tests/049_alineacion_permisos_roles.sql`.
Actualizar la página o cerrar y abrir sesión para volver a consultar permisos.

| Rol | Acceso |
| --- | --- |
| SUPERADMIN | Todos los permisos activos de administración. |
| DIRECTIVA | Todos los permisos activos; crear usuarios SUPERADMIN sigue prohibido por API y RPC. |
| COORDINADOR | Inicio, consulta, creación, edición, cancelación y gestión de participantes de asignaciones de los cinco tipos; respuestas y asistencia propias. |
| MONITOR | Inicio y asignaciones propias, respuestas y asistencia propias. |

El catálogo académico se administra por SUPERADMIN y DIRECTIVA.
Coordinador obtiene las opciones necesarias desde los endpoints de creación de
asignaciones, sin acceso a la administración de colegios, usuarios ni catálogo.
No administra usuarios, colegios ni catálogo. La reapertura de actividades canceladas
sigue reservada a SUPERADMIN y DIRECTIVA por la regla existente. La regularización
de asistencia de terceros se definirá al completar el módulo de asistencia.

Si ya se aplicó 049 antes de ampliar el alcance del coordinador, aplicar 050 para
incorporar UPDATE_ASSIGNMENT, CANCEL_ASSIGNMENT y REASSIGN_ASSIGNMENT.
Actualmente el retiro de una actividad se implementa mediante cancelación auditada,
conservando participantes, respuestas y asistencia; no existe DELETE de asignaciones.

La protección existente de cuentas SUPERADMIN frente a modificaciones de DIRECTIVA
se conserva. La página de Auditoría sigue siendo una pantalla base; su API de
lectura exige VIEW_AUDIT_LOGS y ahora DIRECTIVA también recibe ese permiso.

La migración solo alinea permisos actuales; futuras migraciones deben respetar esta
matriz al incorporar permisos nuevos. No otorga acceso directo a tablas ni RPC
desde clientes anon/authenticated. El backend sigue comprobando permisos y propiedad.
