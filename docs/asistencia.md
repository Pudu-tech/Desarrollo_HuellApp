# Asistencia

Referencia de develop, actualizada el 20-10-2026.
Aceptar una invitación y registrar asistencia son acciones distintas.

## Registro propio

Disponible desde Mis asignaciones → Ver detalle y desde Asistencia / Mi Asistencia
→ Registrar asistencia, en la fila propia. Ambos abren el mismo formulario; desde
el listado se desplaza la página al panel. Backend valida identidad y propiedad.

Una participación aceptada con asistencia pendiente permite PRESENTE, AUSENTE o
JUSTIFICADA; las dos últimas requieren motivo. PostgreSQL comprueba la actividad
y el plazo: desde su inicio hasta 24 horas después del término. Las participaciones
rechazadas se muestran como NO_REQUERIDA.

Es obligatorio Obtener ubicación y aceptar el permiso del navegador. El botón
Registrar asistencia permanece atenuado y deshabilitado hasta tener ubicación
y los campos obligatorios. El mensaje indica «Activa la ubicación para registrar
tu asistencia». Se conservan coordenadas, precisión y fecha, con enlace Ver en mapa.
No hay seguimiento continuo; los datos del dispositivo no prueban infaliblemente
la presencia en el colegio.

## Consulta y regularización

| Rol | Alcance |
| --- | --- |
| MONITOR | Consulta y registro de su asistencia |
| COORDINADOR | Consulta general y vista propia; no regulariza terceros |
| DIRECTIVA | Consulta, registro propio y regularización administrativa |
| SUPERADMIN | Consulta y regularización; no es participante elegible |

Regularizar abre y enfoca el formulario sobre la tabla. Permite PRESENTE, AUSENTE
o JUSTIFICADA, con motivo de regularización y auditoría obligatorios. No requiere
ubicación nueva y conserva la original. Las ausencias requieren además su motivo.
El acceso al registro desde el menú no concede permisos para corregir asistencias
ya guardadas: esa operación sigue siendo administrativa.

Se utilizan VIEW_ASSIGNMENTS, REPORT_ATTENDANCE, MANAGE_ATTENDANCE y las RPC
existentes. El refresco visible se pausa mientras se edita.
Los registros guardados se pueden consultar desde ambos caminos.
El listado permite ordenar por fecha, actividad, colegio/lugar y participante
con las flechas del encabezado, tanto en la vista propia como en la general.

## Dirección legible opcional

GOOGLE_MAPS_API_KEY solo se configura en backend si se habilita Geocoding API.
Sin clave o ante un fallo del proveedor se conservan las coordenadas. El registro
no depende de obtener una dirección. Revisar cuotas/condiciones antes de habilitar
el proveedor; esta guía no acredita una prueba real de geocodificación.

## Pruebas

Desde backend: `python -m unittest discover -s tests`. Las pruebas usan mocks.
En DEV probar permiso GPS, ubicación denegada, ventana horaria, presente y ausencias,
propiedad, coordinación solo lectura y regularización con motivo auditado.
Verificar que Regularizar abre el formulario visible desde el final de una tabla larga.
