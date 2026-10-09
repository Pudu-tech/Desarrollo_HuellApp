# Catálogo académico transversal (046)

Aplicar `supabase/migrations/046_catalogo_academico.sql` después de 045 en DEV/QA
mediante SQL Editor, y luego ejecutar `supabase/tests/046_catalogo_academico.sql`.
El test usa BEGIN/ROLLBACK: sus colegios, asignaturas, espacios y auditorías no
permanecen. La migración sí debe quedar confirmada. Desplegar backend y frontend
juntos después de aplicar 046; las nuevas consultas requieren `ramo_nivel`.

## Modelo e integridad

- `ramos` conserva todos sus IDs. `ramo_nivel` copia el nivel legado de cada
  registro y permite habilitar la misma asignatura en varios grados, sin colegio.
- El campo legado `ramos.nivel_curso_id` pasa a nullable; al administrar un ramo
  se limpia y la relación se convierte en fuente de verdad. La migración no
  cambia asignaciones, participantes, contactos, espacios ni IDs históricos.
- No fusiona ramos antiguos con nombres repetidos entre grados. Se pueden
  identificar y renombrar desde el catálogo; unir su historial requiere una
  decisión y una migración específica. No eliminar duplicados por SQL.
- Nuevas altas y renombres evitan nombres duplicados sin distinguir mayúsculas
  ni espacios exteriores. Los nombres legados sin cambio conservan su validez.
- Desactivar/eliminar asignaturas o espacios, y retirar niveles, se bloquea si
  afecta asignaciones activas no eliminadas desde hoy en America/Santiago,
  excluyendo CANCELADA, REALIZADA y NO_REALIZADA.
- Eliminar una asignatura elimina lógicamente sus espacios; no borra
  asignaciones. Desactivarla conserva el estado individual de sus espacios.
  Reactivarla no reactiva espacios que se hayan desactivado por separado.
- Un espacio no se traslada entre asignaturas. Un curso con referencias
  académicas conserva su grado para no reinterpretar su historial.
- Triggers validan nivel, asignatura y espacio en altas, reprogramaciones y
  reaperturas. Las modificaciones descriptivas históricas siguen permitidas.
  Los bloqueos de filas coordinan estas operaciones con la administración.

## Permisos y auditoría

Se crean VIEW/CREATE/UPDATE/ACTIVATE/DEACTIVATE/DELETE_ACADEMIC_CATALOG.
SUPERADMIN recibe todos; DIRECTIVA y COORDINADOR reciben VIEW. No se conceden
privilegios a MONITOR. FastAPI exige el permiso de cada acción y el RPC vuelve
a comprobarlo contra el actor activo. La tabla de niveles tiene RLS y el RPC
solo puede ser ejecutado por service_role; nunca desde el navegador.

Cada escritura genera auditoría con estado anterior/nuevo, actor, rol,
request_id, IP y user-agent. Los snapshots de asignaturas incluyen nivel_ids.
La cascada genera un audit_log por espacio, con cascade_subject_id y el mismo
request_id. Si falla una auditoría, se revierte toda la escritura.

Endpoints: GET `/catalogo-academico`; POST `/{entidad}`; PUT `/{entidad}/{id}`;
PATCH `/{entidad}/{id}/activate|deactivate`; DELETE `/{entidad}/{id}` (204).
Entidades: asignaturas, reflexion, encuentro. PUT recibe los datos completos.
El cliente no recibe permiso para fijar actor, activo ni deleted_at.

## Prueba desde la aplicación

1. Entrar como SUPERADMIN y abrir **Catálogo académico → Asignaturas**.
2. Crear Matemática para dos niveles activos. No repetirla por colegio.
3. En cada pestaña de espacios seleccionar Matemática y crear un espacio.
4. Abrir Asignaciones y crear una actividad de reflexión/encuentro: seleccionar
   colegio, curso de un nivel habilitado, sala, asignatura, su espacio, contactos,
   participantes y horario. Repetir con otro colegio o grado habilitado.
5. Con una asignación vigente, comprobar el rechazo de desactivación, eliminación
   y retiro del grado correspondiente. Debe conservarse el recurso.
6. Cancelar esa asignación y repetir. Comprobar audit_logs en Supabase y que la reapertura
   no use un recurso eliminado. Una asignatura eliminada no vuelve al selector.
7. Consultar como DIRECTIVA/COORDINADOR: sin botones administrativos; invocar
   endpoints de escritura con ese usuario debe responder 403.

El test SQL cubre permisos, dos grados por asignatura, unicidad, retiro de
niveles, SQL directo, grado histórico, conflictos, cascada y fallo de auditoría.
Las pruebas de transporte frontend usan respuestas simuladas. Los tests Python
requieren un intérprete funcional; no sustituyen la prueba SQL en Supabase.

La página Auditoría actual es una pantalla base. Para consultar los eventos
de este catálogo usar SQL Editor o el endpoint de auditoría existente:

```sql
SELECT created_at, action, entity_type, entity_id, actor_user_id, request_id,
       old_values, new_values
FROM public.audit_logs
WHERE entity_type IN ('SUBJECT', 'REFLECTION_SPACE', 'ENCOUNTER_SPACE')
ORDER BY created_at DESC
LIMIT 50;
```

Para buscar nombres legados repetidos antes de una revisión manual:

```sql
SELECT lower(btrim(nombre)) AS nombre, array_agg(id) AS ids
FROM public.ramos WHERE deleted_at IS NULL
GROUP BY lower(btrim(nombre)) HAVING count(*) > 1;
```
