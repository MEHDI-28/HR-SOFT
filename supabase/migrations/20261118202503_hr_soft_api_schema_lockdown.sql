-- Restrict PostgREST to the public API schemas; HR internals remain private.
ALTER ROLE authenticator SET pgrst.db_schemas = 'public,graphql_public';
ALTER ROLE authenticator SET pgrst.db_extra_search_path = 'public,extensions';
NOTIFY pgrst, 'reload config';
