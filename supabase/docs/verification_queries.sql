-- ============================================================
-- HuellAPP - Verificación del baseline
-- Ejecutar sobre una base donde se haya aplicado el baseline.
-- ============================================================

-- Tablas públicas
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_type = 'BASE TABLE'
order by table_name;

-- Constraints exactas
select
    n.nspname as schema_name,
    c.relname as table_name,
    con.conname as constraint_name,
    case con.contype
        when 'p' then 'PRIMARY KEY'
        when 'f' then 'FOREIGN KEY'
        when 'u' then 'UNIQUE'
        when 'c' then 'CHECK'
        when 'x' then 'EXCLUSION'
        else con.contype::text
    end as constraint_type,
    pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by c.relname, constraint_type, con.conname;

-- RLS
select
    n.nspname as schema_name,
    c.relname as table_name,
    c.relrowsecurity as rls_enabled,
    c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
order by c.relname;

-- Policies: el estado reconstruido esperado es 0 filas.
select *
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
