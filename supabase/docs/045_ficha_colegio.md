# HuellAPP · Ficha del establecimiento y eliminación lógica auditada

## Comportamiento implementado

Se trabajó en `develop`, sobre los contratos existentes. El menú administrativo
conserva Inicio, Usuarios, Colegios, Asignaciones y Auditoría según el rol.
Los accesos antiguos `/app/cursos` y `/app/salas` redirigen a Colegios; sus
páginas independientes se retiraron después de reemplazar sus usos.

Colegios → Editar abre una ficha con Información general, Personas de contacto,
Cursos y Salas. Las secciones se habilitan por los permisos efectivos de la
sesión. Se cargan al abrirlas y permanecen montadas al cambiar de pestaña para
conservar formularios y listados. Las flechas, Inicio y Fin recorren las pestañas.
La navegación queda deshabilitada durante las escrituras. La confirmación de
eliminación del colegio usa un diálogo nativo con control de foco.

Cursos y Salas permiten crear, editar, activar, desactivar y eliminar
lógicamente desde el mismo colegio, sin selector de establecimiento. El
listado se filtra en backend por `colegio_id` y se actualiza con la respuesta
confirmada después de cada operación. El nombre mostrado del curso continúa
generándose en la RPC existente. Los niveles se obtienen de `niveles_curso`
mediante `GET /catalogos/niveles-curso`, protegido por `VIEW_COURSES`.

Contactos conserva sus campos y contratos existentes, con permisos efectivos,
errores de carga distinguibles de una lista vacía y reintento. No se cambia la
autenticación, recuperación de contraseña, invitaciones, Brevo, política de
sesión ni el funcionamiento de Usuarios. Los cambios anteriores en
`/auth/permissions` y la validación de permisos activos se reutilizan.

## Integridad y auditoría

La RPC `eliminar_colegio_atomico` conserva su firma y ahora archiva el colegio
y todos sus cursos, salas y contactos que todavía no estaban eliminados.
Todos reciben `activo=false`, `deleted_at`, `updated_at` y `updated_by` dentro
de la misma transacción. Los hijos previamente eliminados conservan su fecha
y auditoría originales. No se borran asignaciones, participantes ni vínculos
históricos de contactos.

Se registra `DELETE_SCHOOL` y una acción `DELETE_COURSE`, `DELETE_ROOM` o
`DELETE_SCHOOL_CONTACT` por cada hijo afectado. Todas incluyen actor, rol,
snapshots, fecha, request ID, IP y user agent. La auditoría del colegio incluye
los IDs afectados en `new_values.cascada`; cada auditoría hija identifica el
colegio iniciador en su descripción. Si falla cualquier escritura o auditoría,
se revierte toda la cascada.

La eliminación usa `DELETE_SCHOOL`; no amplía privilegios ni requiere que el
actor tenga los permisos de eliminación individual de cada hijo. La 044
concede `DELETE_COURSE` y `DELETE_ROOM` inicialmente a SUPERADMIN. DIRECTIVA
conserva sus permisos existentes. COORDINADOR conserva su navegación actual;
no se abre acceso a la ficha sin revisar sus permisos reales.

Las asignaciones no eliminadas, activas y con fecha desde hoy en
America/Santiago bloquean cuando su estado no es CANCELADA, REALIZADA ni
NO_REALIZADA. Esta distinción es necesaria porque cancelar una asignación
conserva `activo=true`. El backend devuelve 409 y pide cancelar o reasignar.
Los registros inexistentes o ya eliminados devuelven 404; los permisos inválidos,
403; UUID inválidos, 422; eliminación correcta, 204.

Los triggers protegen altas de hijos mientras se elimina el colegio y validan
colegio/curso/sala al crear, reprogramar y reactivar asignaciones. La reapertura
valida además los contactos conservados. La edición general mantiene el
reemplazo de contactos de la RPC 029: los vínculos nuevos se validan después de
actualizar el contexto escolar. Se conserva el máximo de dos contactos; un
bloqueo sobre la asignación serializa su conteo ante inserciones concurrentes.
Las operaciones históricas que no reactivan ni cambian el contexto conservan
sus referencias, incluso cuando el recurso se ha eliminado.

La pertenencia de Cursos, Salas y Contactos queda inmutable en PostgreSQL para
evitar trasladar registros utilizados históricamente. Se conserva el UUID y
los contratos PATCH; intentar cambiar el colegio devuelve 409. Las UNIQUE
actuales de cursos y salas siguen reservando la combinación/nombre incluso
después de eliminar: la reutilización de esas identidades no forma parte de
esta modificación.

## Migraciones y despliegue DEV/QA

1. Verificar cuáles migraciones están aplicadas realmente en DEV/QA.
2. Aplicar `044_eliminacion_logica_cursos_salas.sql` si aún está pendiente.
3. Aplicar `045_ficha_colegio_cascada_logica.sql` después de 044.
4. Ejecutar los scripts de regresión SQL en DEV/QA.
5. Desplegar backend y frontend de `develop` y completar las pruebas manuales.

La migración 045 es incremental e idempotente en sus funciones/triggers. No
edita las migraciones históricas ni concede permisos adicionales. Las RPC
SECURITY DEFINER solo permiten ejecución desde `service_role`; el cliente
usa FastAPI y nunca recibe esta credencial.

La 041 podía dejar hijos vigentes de colegios ya eliminados. La 045 impide
nuevas altas/reactivaciones, pero no reescribe esas eliminaciones anteriores
ni inventa el actor para su auditoría. Antes del despliegue, esta consulta
detecta casos que necesitan revisión y reparación auditada explícita:

```sql
SELECT 'COURSE' AS entidad, c.id, c.colegio_id
FROM public.cursos_colegio c JOIN public.colegios p ON p.id = c.colegio_id
WHERE p.deleted_at IS NOT NULL AND c.deleted_at IS NULL
UNION ALL
SELECT 'ROOM', s.id, s.colegio_id
FROM public.salas s JOIN public.colegios p ON p.id = s.colegio_id
WHERE p.deleted_at IS NOT NULL AND s.deleted_at IS NULL
UNION ALL
SELECT 'SCHOOL_CONTACT', c.id, c.colegio_id
FROM public.contactos_colegio c JOIN public.colegios p ON p.id = c.colegio_id
WHERE p.deleted_at IS NOT NULL AND c.deleted_at IS NULL;
```

## Verificaciones realizadas y límites

- `npm.cmd run build`: TypeScript y Vite pasan. Permanece el aviso existente
  por tamaño del bundle superior a 500 kB.
- `node --experimental-vm-modules --test tests/recursosService.test.mjs` desde
  frontend: seis pruebas de contratos HTTP pasan. Node informa que VM Modules
  es experimental; se usa solo en estas pruebas, sin dependencia nueva.
- Lint de los archivos nuevos/modificados de esta ficha y `git diff --check`:
  pasan. El lint general conserva cinco errores preexistentes en
  ColegioCreateForm, UserCreateForm, UserEditForm, AuthContext y UsuariosPage.
  Esos archivos no se modificaron.
- Backend y SQL revisados sobre esquemas/migraciones existentes, pero **no
  ejecutados contra Supabase real**. El Python local apunta a un intérprete
  inaccesible: no se pudo comprobar sintaxis Python mediante compileall ni
  ejecutar unittest. No hay PostgreSQL local ni navegador automatizado disponible.
  No se ha aplicado ninguna migración ni realizado despliegue remoto.

Pruebas listas para ejecutar con el entorno disponible:

```text
cd backend
python -m compileall -q app tests
python -m unittest discover -s tests

cd frontend
npm.cmd run build
node --experimental-vm-modules --test tests/recursosService.test.mjs
```

Los scripts `supabase/tests/044_eliminacion_logica_cursos_salas.sql` y
`supabase/tests/045_ficha_colegio_cascada_logica.sql` requieren fixtures escolares
de colegio/nivel activos, tipo REUNION y SUPERADMIN activo; crean sus propias
asignaciones y recursos aislados y terminan en ROLLBACK. No requieren asignaciones previas.
Comprueban permisos, bloqueos, snapshots y rollback ante fallo de auditoría.
La 045 comprueba además cascada con hijos inactivos, ausencia de duplicación de
auditoría de hijos ya eliminados, asignaciones canceladas, historial y reapertura.

## Pruebas manuales pendientes

- Con SUPERADMIN y DIRECTIVA, navegar por las cuatro secciones, probar teclado
  y tamaños móviles y verificar visibilidad de acciones según permisos reales.
- Crear/editar/cambiar estado/eliminar cada recurso; comprobar respuesta y
  refresco inmediato sin salir de la ficha. Cambiar de pestaña conserva ediciones.
- Revisar nombres de curso generados por el servidor y niveles activos reales.
- Confirmar que un colegio inactivo no permite altas ni reactivación de hijos.
- Comprobar 403 con llamadas directas sin permiso, 404 de eliminados y 422 de UUID.
- Una asignación de hoy/mañana PENDIENTE o CONFIRMADA debe bloquear eliminación.
  Cancelarla debe liberar el bloqueo sin modificar `activo`.
- Eliminar un colegio con cursos/salas/contactos activos e inactivos; revisar
  auditorías por entidad y los IDs de cascada. Confirmar el historial intacto.
- Intentar reabrir una asignación cancelada cuyos recursos fueron eliminados:
  debe devolver 409 y revertir cualquier cambio de estado/historial/auditoría.
- Editar una asignación reemplazando colegio y contactos válidos; comprobar que
  el contrato existente funciona y que el tercer contacto sigue rechazándose.
- Probar dos transacciones READ COMMITTED: alta de hijo/asignación en A mientras
  B elimina el colegio; B espera y después incluye al hijo o bloquea por la
  asignación. Invertir el orden: tras confirmar la eliminación en A, B rechaza
  el alta/reapertura. Repetir para recursos individuales y altas de contactos.

## Archivos modificados, nuevos y retirados

Modificados, incluyendo los cambios conservados del turno anterior:

- `backend/app/api/asignaciones.py`
- `backend/app/api/auth.py`
- `backend/app/api/catalogos.py`
- `backend/app/api/colegios.py`
- `backend/app/api/cursos.py`
- `backend/app/api/salas.py`
- `backend/app/core/security.py`
- `frontend/src/App.tsx`
- `frontend/src/config/navigation.ts`
- `frontend/src/pages/ColegiosPage.tsx`
- `frontend/src/components/colegios/ColegioEditForm.tsx`
- `frontend/src/components/colegios/ColegioContactos.tsx`
- `frontend/src/styles/colegios.css`

Nuevos, incluyendo los archivos conservados del turno anterior:

- `backend/app/core/resource_integrity.py`
- `backend/tests/test_resource_deletion.py`
- `backend/tests/test_school_management.py`
- `frontend/src/components/colegios/ColegioCursos.tsx`
- `frontend/src/components/colegios/ColegioSalas.tsx`
- `frontend/src/components/colegios/ColegioTabs.tsx`
- `frontend/src/components/colegios/ColegioDeleteDialog.tsx`
- `frontend/src/components/colegios/RecursoEstado.tsx`
- `frontend/src/hooks/useRecursosColegio.ts`
- `frontend/src/services/recursosService.ts`
- `frontend/src/services/cursosService.ts`
- `frontend/src/services/salasService.ts`
- `frontend/src/types/recursos.ts`
- `frontend/tests/recursosService.test.mjs`
- `supabase/migrations/044_eliminacion_logica_cursos_salas.sql`
- `supabase/migrations/045_ficha_colegio_cascada_logica.sql`
- `supabase/tests/044_eliminacion_logica_cursos_salas.sql`
- `supabase/tests/045_ficha_colegio_cascada_logica.sql`
- `supabase/docs/044_eliminacion_cursos_salas.md`
- `supabase/docs/045_ficha_colegio.md`

Retirados por reemplazo confirmado:

- `frontend/src/pages/CursosPage.tsx`
- `frontend/src/pages/SalasPage.tsx`
- `frontend/src/components/RecursosPage.tsx` (creado en el turno anterior).
