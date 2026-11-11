# Carga de pantallas: diagnóstico y cambios

Referencia revisada el 20-10-2026. Las cifras de benchmark y tamaños que aparecen
a continuación son mediciones históricas de cambios anteriores, no métricas del
despliegue actual ni garantías de tiempo de respuesta.

El cliente Supabase instalado en backend es síncrono. Los endpoints y dependencias
que lo usan ahora son funciones `def`, para que FastAPI los ejecute en su pool de
hilos en lugar de bloquear el bucle de eventos. Se conservan firmas, permisos,
transacciones, auditoría y respuestas HTTP. No requiere migración SQL.

El perfil de usuario incluye los permisos activos del rol en una sola consulta.
`require_permission` utiliza ese resultado de la misma petición. No hay caché entre
peticiones: la siguiente petición consulta de nuevo el perfil y los permisos. El
JWT continúa validándose con Supabase Auth. Los permisos internos no se incluyen
en la respuesta pública de `/auth/me`.

`/mi-participacion` obtiene asignaciones y participaciones propias mediante una
consulta con relaciones, reemplazando el patrón de una consulta inicial y dos
consultas adicionales por cada actividad. Se filtra propietario, participación
activa y asignación no eliminada. La lectura individual y las respuestas conservan
sus comprobaciones originales de versión y propiedad.
La lectura individual de la participación también obtiene sus datos y los de la
asignación en una consulta con relaciones. Consultar una invitación requiere además
validar el token y la notificación; no es una única petición a la base en total.

## Medición reproducible

Desde backend: `python tests/benchmark_read_concurrency.py`.
Simula tres listados HTTP con consultas de 150 ms, sin contactar Supabase:

| Versión | Tres peticiones concurrentes, tres repeticiones |
| --- | --- |
| Antes | 514, 456, 458 ms |
| Después | 214, 158, 160 ms |

Esto demuestra eliminación de la espera acumulada; no garantiza estos tiempos en
producción. Consultas de validación de relaciones al Supabase real tardaron 561 ms
(perfil/rol/permisos) y 255 ms (participación/asignación), una muestra por consulta
desde PowerShell. Incluyen red y conexión; no son tiempos completos de pantalla ni
de ejecución SQL. Falta comparar navegación autenticada real desde el navegador.

Cada respuesta devuelve `Server-Timing: app;dur=...` con el tiempo de procesamiento
del backend hasta los encabezados, sin registrar tokens ni datos personales.
En herramientas del navegador, Red/Network, comparar duración de las solicitudes
de asignaciones, colegios y usuarios con este encabezado. No incluye renderizado,
transferencia completa del cuerpo ni todo el recorrido de red.

Reiniciar el backend para activar los cambios. Validar las pantallas con los cuatro
roles, editar una actividad y comprobar el correo y la auditoría. Las pruebas locales
de permisos, eliminación, invitaciones y concurrencia pasan con datos simulados.

Si persiste demora tras este cambio, medir primero las peticiones reales. Evaluar
cantidad de solicitudes del modo de desarrollo, carga anticipada de catálogos,
ubicación del backend respecto de Supabase, paginación e índices según la evidencia.
No se agregaron cachés de autorización, índices ni cambios de región sin mediciones.

## Reutilización al navegar

El frontend conserva respuestas GET autenticadas en memoria hasta dos minutos
(permisos de interfaz: 30 segundos), con un máximo de cien entradas. Se separan por
token de sesión; login/logout y cambios de token descartan los datos anteriores.
No persiste contenido en localStorage. Las solicitudes idénticas simultáneas se
comparten para evitar duplicados al montar pantallas en desarrollo.

Las escrituras invalidan antes de iniciar y después de completarse. Una lectura
anterior que termina después de esa invalidación no repuebla la caché. Actualizar
descarta la caché y consulta al servidor. Los formularios de creación/edición y el
detalle de participación propia siempre consultan datos nuevos. Los errores no se
cachean. Un cambio externo puede tardar hasta dos minutos en aparecer al navegar;
Actualizar lo obtiene inmediatamente. Las acciones siguen autorizadas en backend.

La pantalla de Asignaciones utiliza GET /asignaciones/resumen: una autenticación
para listado, catálogos y permisos de presentación. Listado y catálogos se consultan
en paralelo. Reabrir la pantalla dentro de la vigencia reutiliza esa respuesta,
sin repetir ninguna petición HTTP. Reiniciar backend y recargar frontend para usar
el endpoint nuevo. No requiere SQL. Falta medir la primera carga real autenticada
del navegador; la prueba simulada anterior solo cubre concurrencia del servidor.

## Descarga inicial y filtros

Las páginas, salvo Login, usan importación dinámica con Suspense local: el menú y
layout permanecen visibles al descargar la nueva pantalla. El formulario de crear
o editar asignaciones también se descarga solamente al abrirlo. Los datos de sus
opciones ya se obtenían bajo demanda y continúan consultándose frescos.

La entrada JavaScript pasó de aproximadamente 618 kB a 493 kB sin comprimir, y el
CSS inicial de 40.7 kB a 15.3 kB. Los archivos separados se descargan al navegar;
no se eliminó funcionalidad. Es una reducción del artefacto de producción, no una
medición de segundos de carga del navegador.

Colegios muestra el listado cuando termina su consulta, sin esperar regiones y
dependencias. Los filtros se completan al llegar sus catálogos. Los catálogos maestros
de regiones, comunas, niveles y dependencias se conservan diez minutos en memoria;
Actualizar y cualquier escritura los invalidan. Los datos operativos conservan dos
minutos. Los tres catálogos de lectura de Asignaciones se consultan en paralelo.

## Diagnóstico en Vercel

Comparar duración de solicitudes y Server-Timing en Network; no atribuir toda la
espera a un arranque de la función sin medir. Registrar ruta, commit desplegado,
resultado HTTP y si el problema ocurre al abrir una página o al guardar.
No incluir tokens de invitaciones, cabeceras Authorization ni datos personales.

Las consultas/respuestas de invitación tienen límite de espera de 20 segundos
en el frontend y permiten volver a consultar el estado. Abortar la espera del
navegador no garantiza cancelar una escritura ya iniciada en backend: no reenviar
una respuesta automáticamente por timeout.

Si la pantalla queda en blanco al navegar, conservar el error de Console antes
de actualizar y revisar las descargas de módulos en Network. Un error de ejecución
JavaScript o de carga de un módulo tras un despliegue requiere evidencia distinta
de una API lenta. La causa del caso observado no se ha confirmado.

Para medir entregas de correos, revisar por separado webhook, cola y Brevo según
[Correos en Vercel](correos_vercel.md); no confundirlas con el renderizado del sitio.
