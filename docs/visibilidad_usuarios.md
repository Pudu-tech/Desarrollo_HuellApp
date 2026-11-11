# Visibilidad en Usuarios

El mantenedor aplica las siguientes reglas a las cuentas no eliminadas:

| Actor autenticado | Usuarios visibles |
| --- | --- |
| SUPERADMIN | Todos los roles, incluido SUPERADMIN |
| DIRECTIVA | DIRECTIVA, COORDINADOR y MONITOR; excluye SUPERADMIN |

Se incluyen cuentas activas e inactivas para permitir su administración.
Las cuentas con `deleted_at` siguen excluidas para ambos roles. Los endpoints
continúan exigiendo `VIEW_USERS`; este cambio no concede permisos adicionales.

## Implementación

`backend/app/api/users.py` centraliza la regla en `_visible_users_query` y la
aplica a `GET /users`, `GET /users/{user_id}` y `GET /users/{user_id}/photo`.
El actor procede de la sesión autenticada; no se aceptan roles enviados por el
navegador para decidir qué cuentas mostrar.

Las consultas seleccionan `roles!inner(...)`. Para Directiva se agrega
`roles.codigo != SUPERADMIN`, de modo que PostgREST excluye la fila completa
antes de devolver los datos al frontend. La unión interna es necesaria:
filtrar solo una relación embebida podría devolver el usuario con el rol vacío.

Consultar directamente el UUID o la fotografía de un Superadmin como Directiva
devuelve `404 Usuario no encontrado`, igual que una cuenta inexistente. No se
genera una URL firmada para su fotografía. Las restricciones existentes de
creación, edición, cambio de rol y recuperación de acceso siguen vigentes.

La regla se limita al mantenedor de Usuarios; no modifica el historial de
auditoría ni borra referencias a actores históricos en otros módulos.
No requiere migración SQL ni cambios en el contrato del frontend.

## Verificación

Desde `backend`:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p test_user_visibility.py
```

Las pruebas usan los endpoints FastAPI y el constructor real de consultas
PostgREST con transporte HTTP simulado. Comprueban visibilidad por rol,
cuentas inactivas/eliminadas, intentos de alterar el rol mediante parámetros,
acceso directo al detalle/fotografía y obligatoriedad de `VIEW_USERS`.

Prueba manual: iniciar sesión como Superadmin y revisar todos los roles en
Usuarios; luego iniciar sesión como Directiva y comprobar que no aparecen
Superadmin. El detalle y la foto de un Superadmin deben devolver 404 bajo la
sesión Directiva, incluso si se conoce su UUID.
