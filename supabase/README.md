# HuellAPP · Supabase baseline

Este paquete fue reconstruido el 13-09-2026 a partir de introspección directa del esquema remoto DEV/QA de Supabase.

## Qué contiene

- `migrations/001_baseline_huellapp_schema.sql`
  - Tablas del schema `public`
  - PK, FK, UNIQUE y CHECK confirmados
  - Índices no implícitos
  - Funciones `set_updated_at()` y `prevent_audit_log_modification()`
  - Triggers
  - RLS habilitado en todas las tablas públicas observadas
  - Sin policies RLS, porque `pg_policies` devolvió 0 filas
  - Revocación de acceso directo a `anon`/`authenticated`
  - Grants de tablas a `service_role`

- `migrations/007_add_activate_school_permission.sql`
  - Cambio que ya se ejecutó manualmente en DEV/QA.

- `migrations/008_add_activate_course_permission.sql`
  - Cambio que ya se ejecutó manualmente en DEV/QA.

- `docs/verification_queries.sql`
  - Consultas para comparar una base reconstruida con el esquema esperado.

## Importante sobre 001-006

Los archivos históricos 001-006 originales no existían en el repositorio local y no se recuperó su SQL literal.

Por esa razón, este paquete NO inventa seis migraciones históricas. En su lugar, `001_baseline_huellapp_schema.sql` representa fielmente el estado estructural observado de la base actual.

Esto es intencional: es preferible un baseline trazable y verificable a simular una historia de migraciones que no puede demostrarse.

## Datos maestros / seeds

El esquema fue reconstruido con fidelidad, pero este paquete no intenta adivinar filas de datos maestros que no fueron exportadas durante la introspección (roles, permisos previos, asociaciones, regiones/comunas, etc.).

Las migraciones 007 y 008 presuponen que los roles `SUPERADMIN` y `DIRECTIVA` ya existen.

Antes de usar este paquete para crear un entorno completamente nuevo desde cero, se debe versionar también un seed de datos maestros confirmado desde DEV/QA.

## Uso recomendado

### Base DEV/QA existente
NO ejecutar `001_baseline_huellapp_schema.sql` sobre la base actual. El esquema ya existe.

Guarda estos archivos en el repositorio como baseline/versionado.

### Nueva base Supabase
1. Crear el proyecto Supabase.
2. Aplicar `001_baseline_huellapp_schema.sql`.
3. Aplicar los seeds de datos maestros una vez que estén exportados/versionados.
4. Aplicar las migraciones posteriores que correspondan.
5. Ejecutar `docs/verification_queries.sql`.

## Ruta recomendada

`C:\HuellaApp\supabase\`

Estructura:

```
supabase/
├── migrations/
│   ├── 001_baseline_huellapp_schema.sql
│   ├── 007_add_activate_school_permission.sql
│   └── 008_add_activate_course_permission.sql
├── seeds/
└── docs/
    └── verification_queries.sql
```

## Nota de seguridad

El modelo observado es backend-first:
- RLS activo en las tablas públicas.
- No hay policies para clientes directos.
- `anon` y `authenticated` no tienen grants directos de tabla.
- El backend usa credenciales de servidor (`service_role`/secret key) y aplica autorización por permisos.
