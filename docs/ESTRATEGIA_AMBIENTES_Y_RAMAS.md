# Ambientes y ramas

Referencia del repositorio y del despliegue DEV conocido al 20-10-2026.

| Rama | Propósito |
| --- | --- |
| develop | Integración y pruebas |
| main | Rama estable destinada a producción |
| feature/* | Funcionalidades antes de integrarlas |

La rama de integración es develop, no dev. origin/HEAD apunta actualmente a
develop; eso no convierte sus deployments de Vercel en Production.

## DEV/QA

| Componente | Configuración conocida |
| --- | --- |
| Frontend | https://huellapp-frontend-git-develop-huell-app.vercel.app |
| Backend | https://huellapp-backend-git-develop-huell-app.vercel.app |
| Supabase | Proyecto dev_qa_huella |
| Rama Git | develop |
| Ambiente Vercel observado | Preview |

La rama main dentro de Supabase no es la rama Git main: dev_qa_huella sigue siendo
DEV/QA aunque su panel indique Production. Comprobar Source y commit en Vercel;
la URL sin sufijo de rama no identifica por sí sola el código de desarrollo.

## Configuración y promoción

Los proyectos usan Root Directory frontend y backend respectivamente. Comprobar
Ready y el commit correcto en los proyectos afectados después del push.

VITE_API_URL apunta al backend del mismo ambiente. Las variables Supabase del
frontend son públicas; los secretos solo van en backend. Configurar FRONTEND_URL
y CORS_ORIGINS con los dominios del ambiente. No versionar .env.
Cambiar variables en Vercel requiere un nuevo despliegue.

El webhook usa el dominio estable del backend DEV. El cron de Vercel no ejecuta
en Preview: no hay recuperación diaria automática en el despliegue DEV actual.
Ver [Correos](correos_vercel.md).

Antes de promover a main, validar código/migraciones en DEV/QA y revisar proyectos,
secretos y rama Production de destino. Esta guía no afirma que producción ya esté
configurada. Separar datos y colas de DEV/producción para evitar consumidores cruzados.

## Documentación vigente

- [Asignaciones](MODULO_ASIGNACIONES.md): reglas, participantes y pruebas.
- [Asistencia](asistencia.md): registro propio y regularización administrativa.
- [Correos](correos_vercel.md): webhook, despliegue y recuperación.
- [Rendimiento](rendimiento_carga.md): caché, medición y diagnóstico.

archivo/ conserva el diseño previo para trazabilidad; no es documentación vigente.
