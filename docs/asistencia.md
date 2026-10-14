# Asistencia

Menú administrativo: SUPERADMIN y DIRECTIVA ven y regularizan con motivo auditado; COORDINADOR consulta sin editar. Se reutilizan permisos VIEW_ASSIGNMENTS, REPORT_ATTENDANCE y MANAGE_ATTENDANCE, y las RPC 024/027. No necesita una migración nueva.

En Mis asignaciones → Ver detalle, las participaciones aceptadas pueden informar PRESENTE, AUSENTE o JUSTIFICADA con ubicación solicitada explícitamente. Las dos últimas requieren motivo. PostgreSQL controla el inicio y el límite de 24 horas después del término. Registrar participación no marca asistencia.

Las coordenadas y precisión se conservan; se ofrece Ver en mapa. Para dirección legible, configurar GOOGLE_MAPS_API_KEY exclusivamente en el backend con Geocoding API habilitada y restricciones apropiadas. Sin clave o si falla el proveedor, se registra asistencia y se muestran coordenadas. No se ha configurado ni probado un proveedor real desde este cambio. Consultar cuotas, facturación y términos del proveedor antes de habilitarlo.

El panel administrativo actualiza cada 30 segundos mientras es visible, excepto cuando se está regularizando. Para probar en DEV, desplegar backend y frontend. Verificar permiso GPS en celular, errores de ubicación, ventana horaria, propiedad, coordinación solo lectura, regularización y auditoría. La asistencia es evidencia informada por el dispositivo, no prueba infalible de presencia en el colegio.
