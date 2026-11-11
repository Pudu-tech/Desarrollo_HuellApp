# Recordatorios de instancias

Regla acordada: enviar por el canal existente de correo a participantes **pendientes
de confirmar y aceptados**, tres días calendario antes de la fecha de la instancia,
según `America/Santiago`. Las confirmaciones pendientes tienen prioridad en la cola.
No equivale a exactamente 72 horas antes de la hora de inicio.

## Elegibilidad y contenido

- Instancia activa, sin eliminación lógica, en `PENDIENTE` o `CONFIRMADA`.
- Participación vigente en `PENDIENTE` o `ACEPTADA`, y usuario activo con correo.
- Pendientes: resumen y enlaces personales para aceptar o rechazar.
- Aceptados: resumen, confirmación de que ya aceptaron y enlace al detalle;
  no se les pide confirmar de nuevo ni se registra asistencia.

No se envían recordatorios para rechazos, retiros, usuarios inactivos, instancias
canceladas, eliminadas, realizadas o no realizadas. La elegibilidad se comprueba
al generar, al reservar y de nuevo antes de llamar al proveedor. Como en cualquier
envío externo, un correo que ya está en tránsito no puede retirarse.

## Duplicados, cambios y vencimiento

La unicidad corresponde a participación + versión de invitación + tipo de notificación.
La invitación inicial y el recordatorio son entregas independientes. Repetir el cron
no genera otra entrega para la misma versión, incluso si ya se envió o quedó incierta.
Las reservas exclusivas y la clave de idempotencia del canal existente se conservan.

Los cambios sustantivos, la reprogramación y la reasignación ya renuevan la versión.
Un recordatorio de la versión anterior se cancela al intentar procesarlo. La nueva
versión puede tener otro recordatorio cuando corresponda a su fecha vigente. Si
la instancia se reprograma para menos de tres días, recibe la invitación habitual
por el cambio, sin un recordatorio tardío. Cambiar solo la observación no crea otra versión.

Los recordatorios solo se envían durante el día que corresponde a tres días antes;
si el servicio estuvo caído todo ese día, no se recuperan con un aviso fuera de plazo.
El enlace del correo puede consultarse hasta 24 horas después del término de la
instancia, sujeto a la versión y las reglas habituales de participación.

Los recordatorios no alteran las fechas de recepción/actualización de la invitación
mostradas en la interfaz. Los resultados ambiguos del proveedor quedan `INCIERTA`
y exigen revisión antes de un reintento manual, igual que las invitaciones.

## Activación

1. Aplicar `supabase/migrations/056_recordatorios_instancias.sql` después de 055
   en la base del ambiente elegido. La migración no genera correos por sí misma.
2. Desplegar el backend actualizado con las variables de correo existentes.
3. Asegurar una ejecución diaria de `/internal/notifications/cron`, autenticada
   con `CRON_SECRET`, y el webhook de inserción descrito en `correos_vercel.md`.
   El endpoint primero genera recordatorios y luego procesa hasta 100 trabajos
   durante un máximo de 180 segundos. El webhook procesa la cola sin regenerarla.
4. El cron declarado en `backend/vercel.json` conserva `17 8 * * *` (UTC).
   Según la configuración documentada del proyecto, el ambiente DEV es Preview:
   **tener este archivo no activa por sí solo la programación en ese ambiente**.
   Se necesita un programador que invoque el endpoint o el worker continuo.

Para ejecutar localmente, después de aplicar la migración en una base de pruebas,
usar desde `backend`:

```powershell
.\.venv\Scripts\python.exe -m app.workers.notifications
```

El worker continuo comprueba recordatorios cada 60 segundos; `--once` genera y
procesa un lote y termina. **Estos comandos pueden enviar correos reales** a los
destinatarios de la base configurada. Levantar FastAPI o el frontend no inicia el
worker ni aplica migraciones automáticamente. No ejecutar el worker local contra
otra instancia del mismo ambiente con distinta `FRONTEND_URL`.

## Validación

```powershell
# Desde backend; servicios externos simulados.
.\.venv\Scripts\python.exe -m unittest discover -s tests
```

`supabase/tests/056_recordatorios_instancias.sql` prueba la cola y sus funciones
en una transacción que termina con rollback; ejecutar en una base aislada después
de 056. Comprueba unicidad, reserva, pendientes y aceptados, prioridad, nuevas
versiones, fechas no elegibles, permisos y supresión tras cambios o cancelaciones.
No llama a Brevo. Las pruebas Python verifican el contenido de ambos correos,
la zona horaria de verano/invierno, el disparador y la última validación antes del envío.

La entrega real en el ambiente elegido se valida con destinatarios de prueba,
una instancia fechada tres días después y dos ejecuciones del cron: debe haber
una entrega por participante y versión. No es necesario cambiar el reloj del sistema.
