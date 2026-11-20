-- HR-SOFT Stage 17 | Gate 0 | READ-ONLY DATABASE INVENTORY
-- PostgreSQL / Supabase-compatible catalog inspection.
-- Purpose: capture the REAL development database state before any migration.
-- Safety: this file contains SELECT statements only, inside a READ ONLY transaction.
-- Do not run against production unless separately authorized and reviewed.
-- Recommended: run in DEV using a database role that can inspect catalogs.
-- Output: export each result set separately as CSV/JSON; do not share PII or secrets.

BEGIN TRANSACTION READ ONLY;

-- 01. Server / database / current role context
SELECT current_database() AS database_name,
       current_user AS current_role,
       session_user AS session_role,
       current_setting('server_version') AS postgres_version,
       current_setting('search_path') AS search_path,
       current_setting('transaction_read_only') AS transaction_read_only;

-- 02. Installed extensions
SELECT e.extname, e.extversion, n.nspname AS extension_schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 03. Schemas and owners
SELECT n.nspname AS schema_name,
       pg_get_userbyid(n.nspowner) AS owner,
       n.nspacl AS raw_acl
FROM pg_namespace n
WHERE n.nspname NOT LIKE 'pg_toast%'
  AND n.nspname NOT IN ('information_schema')
ORDER BY n.nspname;

-- 04. Relations: tables, partitioned tables, views, materialized views, foreign tables
SELECT n.nspname AS schema_name, c.relname AS object_name,
       CASE c.relkind WHEN 'r' THEN 'table'
                      WHEN 'p' THEN 'partitioned_table'
                      WHEN 'v' THEN 'view'
                      WHEN 'm' THEN 'materialized_view'
                      WHEN 'f' THEN 'foreign_table'
                      WHEN 'S' THEN 'sequence'
                      ELSE c.relkind::text END AS object_type,
       pg_get_userbyid(c.relowner) AS owner,
       c.reltuples::bigint AS estimated_rows,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       c.reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','p','v','m','f','S')
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname;

-- 05. Columns, types, defaults, nullability, generated/identity metadata
SELECT n.nspname AS schema_name, c.relname AS table_name,
       a.attnum AS ordinal_position, a.attname AS column_name,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
       a.attnotnull AS not_null,
       pg_get_expr(ad.adbin, ad.adrelid) AS default_expression,
       a.attidentity AS identity_kind,
       a.attgenerated AS generated_kind,
       col_description(c.oid, a.attnum) AS column_comment
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attrdef ad ON ad.adrelid = c.oid AND ad.adnum = a.attnum
WHERE a.attnum > 0 AND NOT a.attisdropped
  AND c.relkind IN ('r','p','v','m','f')
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname, a.attnum;

-- 06. Primary, unique, foreign-key, check and exclusion constraints
SELECT n.nspname AS schema_name, c.relname AS table_name,
       con.conname AS constraint_name,
       CASE con.contype WHEN 'p' THEN 'primary_key'
                        WHEN 'u' THEN 'unique'
                        WHEN 'f' THEN 'foreign_key'
                        WHEN 'c' THEN 'check'
                        WHEN 'x' THEN 'exclusion'
                        ELSE con.contype::text END AS constraint_type,
       pg_get_constraintdef(con.oid, true) AS definition,
       con.convalidated AS validated,
       rn.nspname AS referenced_schema,
       rc.relname AS referenced_table
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_class rc ON rc.oid = con.confrelid
LEFT JOIN pg_namespace rn ON rn.oid = rc.relnamespace
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname, con.conname;

-- 07. Indexes and validity
SELECT schemaname AS schema_name, tablename AS table_name,
       indexname AS index_name, indexdef AS definition
FROM pg_indexes
WHERE schemaname NOT LIKE 'pg_%'
  AND schemaname <> 'information_schema'
ORDER BY schemaname, tablename, indexname;

SELECT n.nspname AS schema_name, t.relname AS table_name,
       i.relname AS index_name, ix.indisvalid AS is_valid,
       ix.indisready AS is_ready, ix.indisunique AS is_unique,
       ix.indisprimary AS is_primary
FROM pg_index ix
JOIN pg_class i ON i.oid = ix.indexrelid
JOIN pg_class t ON t.oid = ix.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, t.relname, i.relname;

-- 08. RLS policies (including permissive/restrictive mode and expressions)
SELECT schemaname AS schema_name, tablename AS table_name,
       policyname AS policy_name, permissive, roles,
       cmd AS command, qual AS using_expression,
       with_check AS check_expression
FROM pg_policies
WHERE schemaname NOT LIKE 'pg_%'
ORDER BY schemaname, tablename, policyname;

-- 09. Table-level ACLs and column-level ACLs
SELECT n.nspname AS schema_name, c.relname AS object_name,
       c.relkind AS relation_kind, c.relacl AS relation_acl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','p','v','m','f','S')
  AND n.nspname NOT LIKE 'pg_%'
  AND c.relacl IS NOT NULL
ORDER BY n.nspname, c.relname;

SELECT n.nspname AS schema_name, c.relname AS table_name,
       a.attname AS column_name, a.attacl AS column_acl
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE a.attnum > 0 AND NOT a.attisdropped
  AND a.attacl IS NOT NULL
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname, a.attnum;

-- 10. Database roles and memberships (catalog metadata; no passwords)
SELECT r.rolname, r.rolsuper, r.rolinherit, r.rolcreaterole,
       r.rolcreatedb, r.rolcanlogin, r.rolreplication,
       r.rolbypassrls, r.rolconnlimit, r.rolvaliduntil
FROM pg_roles r
ORDER BY r.rolname;

SELECT parent.rolname AS granted_role,
       member.rolname AS member_role,
       m.admin_option
FROM pg_auth_members m
JOIN pg_roles parent ON parent.oid = m.roleid
JOIN pg_roles member ON member.oid = m.member
ORDER BY parent.rolname, member.rolname;

-- 11. Functions/procedures: signature, owner, security-definer flag and config.
-- Deliberately omits function bodies to reduce risk of exposing embedded secrets.
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.provolatile AS volatility,
       p.proconfig AS routine_config,
       p.proacl AS routine_acl,
       l.lanname AS language
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, p.proname;

-- 12. Triggers (excluding internal FK triggers)
SELECT n.nspname AS schema_name, c.relname AS table_name,
       t.tgname AS trigger_name, pg_get_triggerdef(t.oid, true) AS definition,
       t.tgenabled AS enabled_state
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT t.tgisinternal
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname, t.tgname;

-- 13. Enum types and labels
SELECT n.nspname AS schema_name, t.typname AS enum_type,
       e.enumsortorder AS sort_order, e.enumlabel AS enum_label
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
JOIN pg_enum e ON e.enumtypid = t.oid
ORDER BY n.nspname, t.typname, e.enumsortorder;

-- 14. Sequences and ownership links
SELECT n.nspname AS schema_name, c.relname AS sequence_name,
       pg_get_userbyid(c.relowner) AS owner,
       d.refobjid::regclass AS owned_by_table,
       a.attname AS owned_by_column
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_depend d ON d.objid = c.oid AND d.deptype IN ('a','i')
LEFT JOIN pg_class tc ON tc.oid = d.refobjid
LEFT JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
WHERE c.relkind = 'S'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname;

-- 15. Supabase Storage metadata, if Storage schema exists.
-- Returns bucket/object metadata only. Do NOT export object contents or signed URLs.
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'storage'
ORDER BY table_name;

SELECT schemaname AS schema_name, tablename AS table_name,
       policyname AS policy_name, permissive, roles, cmd,
       qual AS using_expression, with_check AS check_expression
FROM pg_policies
WHERE schemaname = 'storage'
ORDER BY tablename, policyname;

-- 16. Supabase migration ledger presence and versions (if table exists).
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'supabase_migrations'
   OR (table_schema = 'public' AND table_name ILIKE '%migration%')
ORDER BY table_schema, table_name;

-- 17. Application schemas summary: counts by schema/object kind
SELECT n.nspname AS schema_name,
       c.relkind AS relation_kind,
       count(*) AS object_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
GROUP BY n.nspname, c.relkind
ORDER BY n.nspname, c.relkind;

ROLLBACK;
