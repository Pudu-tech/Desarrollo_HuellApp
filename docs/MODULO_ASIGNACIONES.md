# HuellAPP — Módulo de Asignaciones

**Estado:** diseño cerrado / implementación en curso  
**Fecha de referencia:** 15-09-2026

> Este archivo debe mantenerse versionado junto al código. Si una regla de negocio cambia, primero se actualiza esta documentación y luego la implementación.

## 1. Modelo central

`asignaciones` representa la **actividad**.  
`asignacion_participantes` representa las **personas involucradas**.

Una asignación puede tener múltiples participantes, sin límite general.

Un usuario solo puede aparecer una vez dentro de la misma asignación:

```sql
UNIQUE (asignacion_id, usuario_id)
```

## 2. Tipos de actividad

- `ESPACIO_REFLEXION`
- `ESPACIO_ENCUENTRO`
- `REUNION`
- `CAPACITACION`
- `EVENTO_CASA_CENTRAL`

### Creación por rol

| Rol | Reflexión | Encuentro | Reunión | Capacitación | Evento Casa Central |
|---|---:|---:|---:|---:|---:|
| SUPERADMIN | Sí | Sí | Sí | Sí | Sí |
| DIRECTIVA | Sí | Sí | Sí | Sí | Sí |
| COORDINADOR | Sí | Sí | Sí | No | No |
| MONITOR | No | No | No | No | No |

**Regla especial:** SUPERADMIN administra y crea cualquier actividad, pero nunca puede ser participante.

## 3. Campos por tipo

| Campo | Reflexión | Encuentro | Reunión | Capacitación | Evento Central |
|---|---|---|---|---|---|
| colegio | Obligatorio | Obligatorio | Obligatorio | No aplica | No aplica |
| curso | Obligatorio | Obligatorio | Opcional | No aplica | No aplica |
| sala | Obligatorio | Obligatorio | Opcional | No aplica | No aplica |
| ramo | Obligatorio | Obligatorio | No aplica | No aplica | No aplica |
| espacio reflexión | Obligatorio | No aplica | No aplica | No aplica | No aplica |
| espacio encuentro | No aplica | Obligatorio | No aplica | No aplica | No aplica |
| profesor/contacto | 1-2 | 1-2 | 1-2 | Ninguno | Ninguno |
| fecha | Obligatorio | Obligatorio | Obligatorio | Obligatorio | Obligatorio |
| hora inicio/fin | Obligatorio | Obligatorio | Obligatorio | Obligatorio | Obligatorio |
| lugar | No aplica | No aplica | No aplica | Obligatorio | Obligatorio |
| observación | Opcional | Opcional | Opcional | Opcional | Opcional |

Siempre: `hora_fin > hora_inicio`.

## 4. Participación

Tipos:

- `RELATOR`
- `ACOMPANAMIENTO`
- `OBSERVADOR`

`LOCUTOR` está descartado.

Estados:

- `PENDIENTE`
- `ACEPTADA`
- `RECHAZADA`

Una participación rechazada requiere motivo.

## 5. Estado global

Estados de `asignaciones`:

- `PENDIENTE`
- `CONFIRMADA`
- `REALIZADA`
- `CANCELADA`

La asignación pasa a `CONFIRMADA` cuando al menos un participante `RELATOR` acepta.

Los estados `ACEPTADA` y `RECHAZADA` no son estados globales: pertenecen a la participación.

## 6. Alcance del Monitor

MONITOR:

- ve solo asignaciones donde aparece en `asignacion_participantes`;
- acepta/rechaza solo su propia participación;
- registra solo su propia asistencia;
- no modifica, cancela, reasigna ni administra asignaciones ajenas.

El filtro debe aplicarse en backend; poseer `VIEW_ASSIGNMENTS` no otorga visibilidad global.

## 7. Profesores/contactos

`contactos_colegio` mantiene contactos reutilizables.

`asignacion_contactos` relaciona la actividad con sus profesores/contactos.

Para `ESPACIO_REFLEXION`, `ESPACIO_ENCUENTRO` y `REUNION`:

- mínimo 1;
- máximo 2;
- deben pertenecer al mismo colegio de la asignación.

`CAPACITACION` y `EVENTO_CASA_CENTRAL` no admiten contactos.

## 8. Asistencia

Estados:

- `PENDIENTE`
- `PRESENTE`
- `AUSENTE`
- `JUSTIFICADA`

`AUSENTE` y `JUSTIFICADA` requieren motivo.

### Marcación propia

El participante debe conceder ubicación.

Sin una posición válida no puede registrar asistencia.

Se almacenan:

- latitud;
- longitud;
- precisión cuando esté disponible;
- fecha de geolocalización;
- dirección detectada como dato informativo.

No existe seguimiento continuo.

### Regularización

DIRECTIVA y SUPERADMIN pueden regularizar asistencia de terceros.

- GPS no obligatorio.
- `motivo_regularizacion` obligatorio.
- auditoría obligatoria.

## 9. Notificaciones

Se reutilizan:

- `notificaciones`
- `notificacion_envios`

Canales:

- `INTERNA`
- `EMAIL` (Brevo)
- `WHATSAPP` (proveedor a implementar)

WhatsApp debe permitir:

- **Aceptar**
- **Rechazar**

El rechazo solicita motivo antes de completar la acción.

La respuesta modifica `asignacion_participantes`, no directamente la asignación completa.

## 10. Permisos nuevos

- `CREATE_TRAINING`
- `CREATE_CENTRAL_EVENT`
- `ACCEPT_PARTICIPATION`
- `REJECT_PARTICIPATION`
- `REPORT_ATTENDANCE`
- `MANAGE_ATTENDANCE`

Los antiguos `ACCEPT_ASSIGNMENT` y `REJECT_ASSIGNMENT` se retiran al migrar al nuevo modelo.

## 11. Auditoría

`historial_asignacion` conserva eventos globales de la actividad.

Se eliminan del modelo antiguo:

- `usuario_asignado_anterior_id`
- `usuario_asignado_nuevo_id`

Los cambios individuales se representan en `asignacion_participantes` y se registran además en `audit_logs` cuando corresponda.

## 12. Migración

Archivo:

```text
supabase/migrations/010_redisenio_modulo_asignaciones.sql
```

La migración:

1. limpia datos de prueba del módulo;
2. elimina la estructura antigua de asignaciones;
3. crea el nuevo modelo;
4. carga catálogos;
5. agrega restricciones y triggers;
6. actualiza permisos;
7. habilita RLS en las nuevas tablas.

**No ejecutar manualmente en PROD.** Primero DEV/QA, pruebas y luego promoción mediante el flujo de migraciones del proyecto.
