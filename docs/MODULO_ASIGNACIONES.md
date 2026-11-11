# Módulo de Asignaciones

Referencia de develop, actualizada el 20-10-2026. Consolida las antiguas notas
de listado/creación, participantes adicionales y pruebas de contactos/reasignación.

## Modelo y permisos

`asignaciones` representa la actividad; `asignacion_participantes`, las personas
involucradas. Cada participación tiene respuesta y asistencia independientes.
No se admiten participantes activos duplicados; las bajas conservan el historial.

| Rol | Reflexión / Encuentro / Reunión | Capacitación / Evento Casa Central |
| --- | --- | --- |
| SUPERADMIN | Puede crear | Puede crear |
| DIRECTIVA | Puede crear | Puede crear |
| COORDINADOR | Puede crear | No puede crear |
| MONITOR | No puede crear | No puede crear |

Crear requiere CREATE_ASSIGNMENT. Capacitación y Evento requieren además
CREATE_TRAINING y CREATE_CENTRAL_EVENT. La API comprueba permisos efectivos.
SUPERADMIN administra, pero no es participante elegible.
MONITOR consulta y responde solo sus participaciones y registra su asistencia.
Los controles del frontend no reemplazan la autorización en backend/DB.

## Listado y formulario

GET /asignaciones/resumen obtiene listado, catálogos y permisos de presentación.
La pantalla filtra por texto, actividad, estado, colegio y fechas. «Asignada a»
muestra participantes vigentes. Las flechas de Fecha alternan orden ascendente
y descendente, con la hora como desempate. «Ver detalle» abre la ficha.

Los listados comparten flechas para ordenar nombres y fechas en ambos sentidos,
incluidas las vistas propias de monitor, coordinación y directiva. También se
ordenan las actividades de Inicio, los participantes del detalle, Colegios,
cursos, salas, contactos y Catálogo académico. Los nombres usan comparación
en español y orden natural de números; las fechas vacías quedan al final.
Auditoría ordena por fecha o actor en backend antes de paginar, conservando filtros.

El selector de colegios excluye inactivos y eliminados; sus nombres se conservan
en el catálogo para interpretar asignaciones históricas. Actualizar descarta la caché.

Crear consulta opciones nuevas al abrir el formulario. Los participantes elegibles
son DIRECTIVA, COORDINADOR y MONITOR activos, con nombre, rol y correo visibles.
No se concede acceso al mantenedor de Usuarios ni se exponen credenciales.
Cambiar actividad/colegio limpia referencias dependientes; cambiar curso limpia
ramo/espacios y cambiar ramo limpia espacios. Las respuestas tardías no deben
mezclar opciones de colegios distintos.

| Actividad | Contexto requerido | Contactos |
| --- | --- | --- |
| Espacio de Reflexión | Colegio, curso, sala, ramo y espacio de reflexión | Al menos uno |
| Espacio de Encuentro | Colegio, curso, sala, ramo y espacio de encuentro | Al menos uno |
| Reunión | Colegio; curso y sala opcionales | Al menos uno |
| Capacitación | Lugar, sin contexto escolar | No admite |
| Evento Casa Central | Lugar, sin contexto escolar | No admite |

Todas requieren participante, tipo de participación, fecha y hora_fin > hora_inicio.
La observación es opcional. Los contactos deben estar activos, no duplicarse y
pertenecer al colegio. Desde la migración 052 se permiten tres o más: no existe
el antiguo máximo de dos contactos.

POST /asignaciones usa crear_asignacion_atomica. Actor, estados iniciales,
invitaciones, asistencia y auditoría se determinan en backend/DB.
El detalle ofrece edición, cancelación, reapertura y gestión de participantes
según permisos y estado; no es una pantalla provisional.

## Participación y gestión de personas

Tipos: RELATOR, ACOMPANAMIENTO y OBSERVADOR.
Respuestas: PENDIENTE, ACEPTADA y RECHAZADA; rechazar requiere motivo.
La respuesta desde correo y web modifica la misma participación.
Estados globales: PENDIENTE, CONFIRMADA, REALIZADA, NO_REALIZADA y CANCELADA.
La aceptación de un relator puede confirmar la actividad según las reglas de DB.
«Por reasignar» es una proyección del listado, no otro estado global.

SUPERADMIN, DIRECTIVA y COORDINADOR pueden agregar participantes a actividades
pendientes o confirmadas con los permisos correspondientes. Se excluyen personas
con participación activa; cada nueva incorporación genera invitación y asistencia.
Cambiar participante y Quitar participante requieren confirmación y
REASSIGN_ASSIGNMENT. Pueden aplicarse a participaciones pendientes o aceptadas
cuando la actividad lo permite. El reemplazo conserva el tipo, archiva la
participación anterior y genera una invitación nueva. La reasignación de rechazos
ofrece monitores activos. Retirar al último relator aceptado de una actividad
confirmada la devuelve a pendiente mediante las funciones existentes.

La eliminación lógica excluye la asignación de las lecturas propias y conserva
historial/auditoría. El refresco al recuperar el foco y mientras la pantalla es
visible refleja cambios externos en la siguiente consulta disponible.

## Asistencia y correos

Aceptar no registra asistencia. El registro propio exige ubicación, participación
aceptada y la ventana horaria validada por PostgreSQL.
Ver [Asistencia](asistencia.md) para registro y corrección administrativa.

Supabase guarda notificaciones internas y entregas pendientes; el webhook invoca
la API de Vercel, que procesa la cola con Brevo. La plantilla muestra primero el
resumen y después Aceptar/Rechazar. Abrir el enlace no responde automáticamente.
Ver [Correos en Vercel](correos_vercel.md) para configuración y recuperación.
WhatsApp no forma parte del envío de invitaciones implementado en este flujo.

## Catálogos y migraciones

| Endpoint GET | Permiso / uso |
| --- | --- |
| /catalogos/asignaciones | VIEW_ASSIGNMENTS; catálogos administrativos e históricos |
| /catalogos/asignaciones/creacion | CREATE_ASSIGNMENT; opciones autorizadas |
| /catalogos/asignaciones/colegios/{id} | CREATE_ASSIGNMENT; cursos, salas y contactos activos |
| /catalogos/asignaciones/ramos/{id}/espacios | CREATE_ASSIGNMENT; espacios del ramo |
| /catalogos/asignaciones/edicion | UPDATE_ASSIGNMENT; opciones de edición |

historial_asignacion conserva eventos globales y audit_logs acciones auditables.
Las migraciones viven en supabase/migrations; sus pruebas SQL, en supabase/tests.
La 010 introdujo el rediseño inicial; las posteriores corrigen/amplían el modelo.
No volver a ejecutar migraciones ya aplicadas. Validar en DEV/QA antes de promover.

El [diseño original](archivo/Diseno_Tecnico_Modulo_Asignaciones_HuellAPP.docx)
se conserva como antecedente de septiembre de 2026, no como especificación vigente.

## Invitaciones de acceso de usuarios

Usuarios → Editar → Acceso y contraseña → Enviar nueva invitación utiliza
Supabase Auth/SMTP, no la cola de actividades. SUPERADMIN y DIRECTIVA requieren
UPDATE_USER; DIRECTIVA no recupera cuentas SUPERADMIN. Se utiliza el correo actual
del perfil y se audita antes de contactar al proveedor. Una solicitud no demuestra
entrega. Autorizar /restablecer-password en las Redirect URLs de Supabase Auth.

## Verificación

Desde backend: `python -m unittest discover -s tests`.
Desde frontend:

```powershell
npm.cmd run build
node --experimental-vm-modules --test tests/recursosService.test.mjs
node --test tests/asignacionesListado.test.mjs
```

Las pruebas simuladas no reemplazan la aceptación en DEV/QA:

1. Probar filtros, nombres de participantes, correos y ambos órdenes de fecha.
2. Crear los cinco tipos con roles permitidos; comprobar detalle y auditoría.
3. Probar tres contactos o más, duplicados y horarios invertidos.
4. Cambiar colegio/curso/ramo durante la carga y comprobar referencias limpias.
5. Desactivar un recurso antes de guardar: rechazar sin creación parcial.
6. Agregar, cambiar y quitar participantes, conservando historial e invitaciones.
7. Rechazar, reasignar y aceptar por correo; verificar el resultado en web.
8. Comprobar roles sin permisos, teclado y móvil.
9. Probar recuperación de acceso desde roles autorizados sin confundirla con actividades.
