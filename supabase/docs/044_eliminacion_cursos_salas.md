# Eliminación lógica de Cursos y Salas

La migración 045 amplía estas reglas para la ficha del colegio y la cascada:
consulta [la guía vigente](045_ficha_colegio.md). Cursos y Salas ahora se
administran dentro de Editar Colegio. Las canceladas/finalizadas dejan de
bloquear la eliminación y su reapertura exige recursos disponibles.

Aplicar `migrations/044_eliminacion_logica_cursos_salas.sql` después de la 043,
antes de desplegar los endpoints DELETE. La migración no elimina registros.
Los permisos `DELETE_COURSE` y `DELETE_ROOM` se conceden inicialmente a SUPERADMIN;
la interfaz consulta los permisos efectivos en `GET /auth/permissions`.

`DELETE /cursos/{id}` y `DELETE /salas/{id}` devuelven 204 al completar la
transacción, 403 sin permiso, 404 para registros inexistentes/eliminados y 409
cuando hay asignaciones activas no eliminadas desde hoy (America/Santiago).
El registro queda con `activo=false`, `deleted_at`, `updated_at` y `updated_by`.
La auditoría conserva actor, rol, snapshots, request ID, IP y user agent.
Un fallo al insertar auditoría revierte la eliminación.

No se modifican las asignaciones históricas ni las restricciones de unicidad:
un curso eliminado sigue reservando colegio/nivel/sección/año y una sala
eliminada sigue reservando colegio/nombre. No hay restauración desde activar.

El trigger `trg_proteger_recursos_asignacion` valida nuevas referencias,
cambios de colegio/fecha, reactivaciones y transiciones futuras de estado.
Bloquea los recursos con FOR SHARE en orden curso/sala; las RPC de eliminación
usan FOR UPDATE. Esto coordina inserciones, ediciones y reaperturas concurrentes.
Una actualización histórica de observación conserva las referencias originales.
La creación no permite recursos eliminados/inactivos, incluso con fecha pasada.

## Validación

- Desde `backend`, ejecutar `python -m unittest discover -s tests`.
- En DEV/QA, ejecutar `tests/044_eliminacion_logica_cursos_salas.sql` con un
  usuario SQL autorizado. Sus fixtures requieren colegio/nivel activos, REUNION
  y SUPERADMIN; no requieren asignaciones previas. Crean recursos aislados y
  todo se revierte con ROLLBACK. Comprueba permisos, asignaciones de hoy,
  rollback por fallo de auditoría, conservación de historial, repetición de
  eliminación y rechazo de creación/reprogramación/reactivación.
- Con sesión SUPERADMIN, confirmar eliminación en ambas páginas; comprobar
  desaparición de la fila solo después de 204. Con un rol sin permiso, verificar
  ausencia de la acción y rechazo 403 al llamar directamente al endpoint.
- Probar un UUID inválido (422), uno inexistente (404) y un recurso con una
  asignación de hoy/mañana (409, sin cambios ni auditoría de eliminación).

## Prueba de concurrencia en dos conexiones DEV/QA

Usar fixtures descartables y transacciones READ COMMITTED. En conexión A,
insertar una asignación activa futura con recursos válidos y dejar la transacción
abierta. En B, llamar a la RPC de eliminación del curso/sala utilizado. B debe
esperar; al confirmar A, B debe devolver `*_HAS_FUTURE_ASSIGNMENTS`. Repetir
invirtiendo el orden: A elimina un recurso sin asignaciones futuras y deja la
transacción abierta; B intenta insertar o reprogramar una asignación hacia él.
Después de confirmar A, B debe fallar con `ASSIGNMENT_RESOURCE_UNAVAILABLE`.
Repetir para curso y sala y para reapertura de asignación cancelada futura.

La ejecución de pruebas Python/SQL requiere un intérprete funcional y una base
de prueba. Esta documentación no sustituye su ejecución antes del despliegue.
