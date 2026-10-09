# HuellAPP · Listado y creación de Asignaciones

## Alcance implementado en develop

La página provisional se reemplaza por un listado conectado a `GET /asignaciones`,
con la presentación de Usuarios/Colegios: encabezado, panel, filtros, tabla,
badges, formulario responsive y confirmación compartida. Se filtra por texto,
tipo, estado, colegio y fechas, sobre la respuesta existente del backend.

`Crear asignación` consulta permisos efectivos y aparece con CREATE_ASSIGNMENT.
Las opciones proceden de las tablas reales; no se introducen catálogos locales
ni se amplían permisos de Usuarios. Los participantes elegibles solo exponen
ID, nombre y rol, y excluyen SUPERADMIN según la regla existente.

El formulario respeta las combinaciones ya validadas por FastAPI:

| Actividad | Contexto requerido | Contactos |
| --- | --- | --- |
| Espacio de Reflexión | Colegio, curso, sala, ramo y espacio de reflexión | 1–2 |
| Espacio de Encuentro | Colegio, curso, sala, ramo y espacio de encuentro | 1–2 |
| Reunión | Colegio; curso y sala opcionales | 1–2 |
| Capacitación | Lugar, sin contexto escolar | Ninguno |
| Evento Casa Central | Lugar, sin contexto escolar | Ninguno |

Todas requieren al menos un participante con su tipo de participación, fecha
y hora de término posterior a la de inicio. No permite usuarios/contactos
duplicados. Capacitación y Evento mantienen CREATE_TRAINING y CREATE_CENTRAL_EVENT
respectivamente, además de CREATE_ASSIGNMENT. El servidor filtra las actividades
disponibles según esos permisos activos y vuelve a validarlas al crear.

Cambiar actividad/colegio limpia sus referencias; cambiar curso limpia ramo y
espacios; cambiar ramo limpia espacios. Los ramos se ofrecen según el nivel
del curso. Las respuestas tardías no mezclan recursos de diferentes colegios.
Los recursos activos no eliminados se consultan por el colegio seleccionado,
y los espacios se consultan por ramo activo. Si falta un catálogo necesario,
se informa al usuario y se ofrece reintento para las consultas dependientes.

El formulario reutiliza `POST /asignaciones` y `crear_asignacion_atomica`.
Actor, estado inicial, participantes pendientes, asistencias y auditoría se
determinan en backend/DB. No se envían desde la interfaz. Después de 201, la
asignación aparece inmediatamente y los filtros se restablecen para mostrarla.
El detalle deja de ser una demostración y muestra un resumen real persistido.

Este cambio implementa listado, creación y resumen de consulta. No incorpora
todavía la interfaz de edición, cancelación, reapertura, respuestas de los
participantes o asistencia; sus endpoints y lógica histórica se conservan.

## Endpoints de lectura añadidos

- `GET /catalogos/asignaciones`: VIEW_ASSIGNMENTS; nombres de actividad, estado
  y colegio para gestión, incluyendo nombres históricos. MONITOR conserva su
  flujo propio y no utiliza este catálogo administrativo.
- `GET /catalogos/asignaciones/creacion`: CREATE_ASSIGNMENT; actividades
  autorizadas, colegios activos, participantes elegibles, tipos y ramos.
- `GET /catalogos/asignaciones/colegios/{id}`: CREATE_ASSIGNMENT; cursos, salas
  y contactos activos no eliminados del colegio validado.
- `GET /catalogos/asignaciones/ramos/{id}/espacios`: CREATE_ASSIGNMENT;
  espacios activos no eliminados del ramo validado.

Los contratos nuevos son proyecciones de consulta; no cambian las tablas ni el
payload existente de POST. **No se requiere una migración adicional.** Debe
actualizarse el backend DEV/QA antes de utilizar los nuevos selectores desde
el frontend; un backend anterior responderá 404 a estos endpoints.

## Validación

Realizada localmente:

- Build de TypeScript/Vite aprobado. Persiste el aviso previo del bundle >500 kB.
- Lint de los archivos de Asignaciones aprobado.
- Diez pruebas del transporte y reglas frontend aprobadas, incluyendo los cinco
  tipos de actividad, contexto prohibido, horario, duplicados y contactos máximos.

Comandos:

```text
cd frontend
npm.cmd run build
node --experimental-vm-modules --test tests/recursosService.test.mjs
```

Python: se intentó `python -m compileall -q app tests` con el entorno del repo,
pero no pudo iniciar porque el intérprete al que apunta `.venv` no es accesible.
Las pruebas de catálogo están preparadas en `backend/tests/test_asignacion_catalogos.py`
y deben ejecutarse con `python -m unittest discover -s tests` cuando se repare
el entorno. No se probó la creación nueva contra Supabase real ni en navegador.

## Pruebas manuales DEV/QA pendientes

1. Cargar listado, aplicar filtros, reintentar una consulta fallida y abrir un
   detalle real. Comprobar fechas/horarios sin desplazamientos de zona horaria.
2. Crear una Reunión con colegio, un contacto y un participante; verificar 201,
   aparición inmediata, detalle y CREATE_ASSIGNMENT en audit_logs.
3. Crear Reflexión y Encuentro con sus ramos/espacios. Cambiar colegio/curso/ramo
   durante la carga para verificar limpieza y descarte de respuestas tardías.
4. Crear Capacitación y Evento con permiso especial: solo debe pedirse lugar
   y participantes. Un rol sin permiso especial no debe ver ese tipo.
5. Intentar contactos duplicados, más de dos, participantes duplicados y horario
   invertido. Verificar que no se genera una escritura y conservar el formulario.
6. Eliminar o desactivar un recurso en otra sesión antes de guardar: el backend
   debe rechazar la selección, sin una asignación parcialmente creada.
7. Con un rol sin CREATE_ASSIGNMENT, comprobar ausencia del botón y rechazo 403
   a POST/catálogos de creación. COORDINADOR no recibe el listado administrativo
   de Usuarios; solo la proyección necesaria para participantes autorizados.
8. Probar teclado, confirmación/cancelación y pantallas móviles. Las operaciones
   de historial, participación y asistencia existentes mantienen sus contratos.

## Archivos

Modificados:

- `backend/app/main.py`
- `backend/app/api/asignaciones.py` (permiso especial activo)
- `frontend/src/pages/AsignacionesPage.tsx`
- `frontend/src/pages/AsignacionDetallePage.tsx`
- `frontend/src/services/recursosService.ts` (documentación del transporte compartido)
- `frontend/tests/recursosService.test.mjs`

Nuevos:

- `backend/app/api/asignacion_catalogos.py`
- `backend/app/schemas/asignacion_catalogos.py`
- `backend/tests/test_asignacion_catalogos.py`
- `frontend/src/types/asignaciones.ts`
- `frontend/src/services/asignacionesService.ts`
- `frontend/src/hooks/useOpcionesDependientes.ts`
- `frontend/src/components/asignaciones/asignacionForm.ts`
- `frontend/src/components/asignaciones/AsignacionParticipantes.tsx`
- `frontend/src/components/asignaciones/AsignacionCreateForm.tsx`
- `frontend/src/styles/asignaciones.css`
- `docs/asignaciones_listado_creacion.md`
