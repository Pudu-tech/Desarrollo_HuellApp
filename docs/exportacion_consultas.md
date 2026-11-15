# Exportación de consultas — incremento 1: Usuarios

## Alcance y fuentes

Decisión de Matías, 15-11-2026: avanzar una vista a la vez, en orden Usuarios → Instancias → Asistencia. Descargar únicamente las columnas del listado, manteniendo orden y diseño adaptado a XLSX/PDF. Botón Exportar sobre el extremo derecho de la tabla, selector de formato y corte único preparado por el servidor.

Relacionado con https://github.com/Pudu-tech/Desarrollo_HuellApp/issues/63 y el borrador CA-10. Este cambio no publica/actualiza issues ni acredita aceptación de Fundación Huella. Instancias y Asistencia se implementarán en los incrementos siguientes; sus filtros todavía no se exportan.

Antes: Usuarios listaba datos de GET /users y no permitía descargar archivos. Después: Exportar ofrece Excel (.xlsx) y PDF con RUT, nombre, correo, teléfono, rol y estado. No incluye Acciones, UUID, fotografías ni objetos internos. Se reutilizan el nombre completo y el comparador de la vista.

### Pauta de interfaz para Usuarios y siguientes vistas

Corrección de Matías: las acciones del listado comparten un mismo div y una fila alineada; no reservar una línea adicional ni un espacio vacío para Exportar. Actualizar conserva el estilo secundario blanco y Exportar usa teal sólido; Crear mantiene su tratamiento propio. En pantallas estrechas se admite envolver la fila para evitar desbordes.

Exportar abre un desplegable anclado debajo del botón, con únicamente Excel (.xlsx) y PDF. No abre un modal ni oscurece el contenido. Se cierra al elegir, pulsar Escape, salir con Tab o hacer clic fuera. Soporta flechas, Inicio/Fin, foco visible y retorno al botón al cerrar o terminar la generación. Los errores aparecen junto al control y las confirmaciones se anuncian sin ocupar una fila vacía. Durante la descarga se muestra Preparando… y se bloquean doble envío, actualización y cambios de orden. Este componente y su contenedor de acciones se reutilizarán en Instancias y Asistencia.

## Decisión técnica vigente

Matías eligió reemplazar la RPC por una única consulta de datos desde FastAPI mediante el cliente Supabase existente, solicitando filas y conteo exacto en la misma petición. Solo se permite descargar cuando el conteo coincide con las filas recibidas. Esta decisión sustituye la implementación inicial con la migración 057: el archivo se retira de migrations y no se necesita aplicar SQL en Supabase. No se agrega una conexión directa a PostgreSQL.

## Comportamiento y permisos

- SUPERADMIN y DIRECTIVA necesitan VIEW_USERS vigente. La identidad procede de FastAPI; nunca se acepta un actor enviado por el navegador.
- Directiva excluye SUPERADMIN; ambos roles excluyen eliminados e incluyen usuarios inactivos, conforme al mantenedor vigente.
- Cada elección de formato solicita GET /exports/users sin caché. FastAPI consulta usuarios y roles!inner con count='exact', excluye usuarios borrados lógicamente y reutiliza _visible_users_query del mantenedor para excluir Superadmin de Directiva. Hay una sola llamada execute(), sin HEAD previo ni páginas adicionales. Los controles de autenticación y permisos habituales siguen ejecutándose antes de esa consulta de datos.
- PostgREST devuelve las filas y el total exacto de la consulta filtrada en esa misma respuesta. Si el total es mayor que las filas recibidas, se devuelve 422 sin datos exportables; no se intenta descargar el resto mediante otra consulta. Si falta un conteo válido o es incoherente, se devuelve 503 y no se infiere que la respuesta está completa.
- Al recibir el corte completo, la tabla se actualiza con esas mismas filas. El orden elegido se conserva: la tabla queda temporalmente inerte y Actualizar/Crear se deshabilitan durante la preparación. El desplegable no bloquea la pantalla como un modal. El corte representa la consulta al servidor, no una copia antigua de la caché.
- Se incluyen todas las filas de esa consulta, sin enriquecerla con detalles de otras pantallas. Usuarios actualmente no tiene búsqueda ni filtros. Los futuros adaptadores deberán compartir los filtros aplicados con sus vistas.
- Cero filas: botón deshabilitado; si el corte devuelve cero, aviso sin archivo. Fallo, falta de sesión/permisos o resultado incoherente: mensaje y posibilidad de reintentar, sin descarga parcial. Doble clic bloqueado y el menú se cierra al elegir formato.
- Se solicitan como máximo 10.000 usuarios como salvaguarda de memoria; el límite efectivo puede ser menor por la configuración de Supabase. No se presupone que sea 1.000 ni se modifica. La descarga se acepta únicamente cuando el total exacto y la cantidad recibida coinciden y no superan 10.000. Incluso si se devuelve justo el límite, se acepta cuando el conteo confirma que no falta ninguna fila.
- El corte corresponde a los datos de esa única respuesta. generated_at indica el inicio de preparación en el backend (UTC, mostrado en America/Santiago); no es un timestamp obtenido de PostgreSQL. No se promete exportar conjuntos que requieran varias respuestas. El conteo se calcula sobre los mismos filtros de visibilidad, no sobre todos los usuarios sin autorización.

## Formatos

Diseño tabular con colores Huella, bordes, estados y encabezados. PDF A4 horizontal, texto seleccionable, fuente Noto Sans local, encabezados repetidos y número de página. XLSX con hoja Usuarios, encabezado fijo, filtro, ajuste de texto y hoja Consulta con fecha del corte, zona America/Santiago, orden y total.

RUT, teléfonos y valores ingresados se escriben como cadenas explícitas; nunca como fórmulas, macros o hipervínculos. Se conservan ceros iniciales, signo + y tildes. Los archivos no contienen controles de la interfaz. Cada formato adapta tamaños y paginación; no es una captura de pantalla del navegador.

Dependencias: ExcelJS, jsPDF y jsPDF-AutoTable, importadas bajo demanda. Override de uuid de ExcelJS a ^11.1.1 para eliminar el aviso de la versión transitoria anterior; compatibilidad de escritura/apertura comprobada. Noto Sans Regular/Bold y licencia SIL OFL en frontend/public/fonts, obtenidas de https://github.com/notofonts/noto-fonts (hinted/ttf/NotoSans). Las bibliotecas mantienen sus avisos de licencia de distribución.

## Componentes

- backend/app/api/user_exports.py y registro en app/main.py: API y validación del corte.
- frontend/src/components/common/ExportButton.tsx y styles/export.css: selector, progreso y errores.
- frontend/src/utils/queryExport.ts: generación compartida de ambos formatos.
- frontend/src/utils/usersExport.ts: proyección de las columnas de Usuarios.
- frontend/src/pages/UsuariosPage.tsx: entrada habitual y sincronización del listado.
- frontend/src/services/readCache.ts: exclusión de exportaciones de la caché.
- package.json/package-lock.json, fuentes y pruebas correspondientes.

## Aplicación y ejecución

1. No se requieren migraciones para la exportación de Usuarios. Usar el esquema y la configuración existentes; no ejecutar la propuesta retirada 057.
2. Desde frontend, ejecutar npm ci para sincronizar las dependencias; npm run dev para iniciar. Desde backend, iniciar uvicorn app.main:app con la configuración habitual.
3. Abrir Usuarios como Directiva/Superadmin, ordenar por nombre y seleccionar Exportar → Excel o PDF. Comprobar que la tabla actualizada coincide con las seis columnas y el orden del archivo.
4. Repetir en DEV/QA con ambas cuentas y verificar que Directiva no obtiene Superadmin. No cargar datos personales reales en una issue pública.

No se ejecutó SQL ni se modificó Supabase. Si la función propuesta anteriormente ya se hubiera aplicado por otra vía, queda sin uso: este cambio no la invoca ni la elimina del servidor. El listado original continúa usando GET /users. La validación de la nueva lectura en DEV/QA sigue pendiente.

## Verificación del 15-11-2026

| Criterio | Estado | Evidencia | Pendiente |
| --- | --- | --- | --- |
| Acciones alineadas y formatos en desplegable | Verificado localmente | Edge con datos ficticios: misma fila/altura, menú sin desplazar tabla ni modal, ratón, flechas, Inicio/Fin, Tab, Escape, cierre exterior, descarga Excel, error sin descarga y retorno de foco; escritorio y móvil de 360 px. Build y lint dirigido correctos | Recorrido autenticado DEV/QA y revisión de Matías |
| Seis columnas y orden del listado | Verificado localmente | usersExport.test.mjs: asc/desc, proyección, tildes, nulos, datos intactos | Aceptación visual por Matías |
| Respuesta única, conteo exacto y visibilidad | Verificado localmente | test_user_export_query.py: constructor PostgREST real, transporte HTTP simulado, una petición GET con count=exact; Directiva/Superadmin, inactivos/eliminados, vacío, truncamiento del servidor, conteo ausente/incoherente, límite exacto y 1.001 filas completas | Probar Supabase real y sus límites configurados |
| Permisos API, fallos y límites | Verificado localmente | 12 pruebas backend/tests/test_user_export_query.py, incluyendo rechazo de otros roles, VIEW_USERS, errores sanitizados y 10.001 filas sin descarga parcial | Prueba HTTP autenticada |
| Excel válido y textos seguros | Verificado localmente | XLSX de 130 filas reabierto con ExcelJS: seis columnas, RUT con ceros, teléfono + y =SUM(...) como texto | Apertura manual en Excel del cliente |
| PDF legible | Verificado localmente | PDF de 130 filas/8 páginas, renderizado con Poppler e inspección visual de primera, segunda y última página; prueba breve y descarga en Edge | Revisión final de Huella |
| Sin caché entre cortes | Verificado localmente | readCache.test.mjs | — |
| Compilación y análisis | Build correcto; lint de archivos cambiados correcto | npm run build y eslint dirigido | Lint general con cuatro errores ajenos al cambio: ColegioCreateForm, UserCreateForm, AuthContext y participacionesService |

Pruebas reproducibles desde frontend: node --test tests/usersExport.test.mjs tests/listSort.test.mjs; node --experimental-vm-modules --test tests/readCache.test.mjs. Desde backend: python -B -m unittest discover -s tests -p test_user_export_query.py.

Evidencia histórica del primer incremento: harness PostgreSQL de la alternativa RPC retirada, harness de navegador, archivos ficticios y capturas en incremento_exportacion_usuarios/repo/verification y frontend/.export-qa. La prueba antigua de PostgreSQL no valida esta nueva lectura; sus pruebas vigentes son test_user_export_query.py. No cambió el contrato del frontend ni los generadores de archivos. La auditoría npm --omit=dev del primer incremento informó cero vulnerabilidades. Permanecen avisos en herramientas de desarrollo existentes y chunks grandes de los generadores diferidos.

No se propone cerrar #63: este es el primer adaptador y faltan validaciones en ambiente y los siguientes incrementos.
