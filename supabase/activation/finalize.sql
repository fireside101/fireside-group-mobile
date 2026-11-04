-- Finalize the combined install, still paused. No fleet-max assertion.
ALTER ROLE mobile_release_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE mobile_release_publisher NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE mobile_release_reader NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE mobile_release_operator NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE mobile_release_registry_login LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3;
GRANT USAGE ON SCHEMA mobile_release TO mobile_release_registry_login;
GRANT EXECUTE ON FUNCTION mobile_release.allocate(text,text,text),mobile_release.reserve(text,text,integer,text),mobile_release.advertise(jsonb),mobile_release.receipt(text),mobile_release.latest() TO mobile_release_registry_login;
INSERT INTO mobile_release.app(singleton,floor,signer,paused,storage_base)
VALUES(true,5,'701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9',true,'https://supabase.firesideafrica.cloud/storage/v1/object/authenticated/fireside-mobile-releases');
-- Never grant reader/publisher direct base-table rights or expose mobile schema.
-- Recheck implicit defaults, effective column-only grants and function owners.
DO $assert$
DECLARE r text; t record; p record;
BEGIN
 FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'mobile_release_%' LOOP
  IF EXISTS(SELECT FROM pg_auth_members WHERE member=r::regrole) THEN RAISE EXCEPTION 'Outbound membership rejected'; END IF;
  IF has_schema_privilege(r,'mobile_release','CREATE') AND r<>'mobile_release_owner' THEN RAISE EXCEPTION 'Schema CREATE rejected'; END IF;
  FOR t IN SELECT oid FROM pg_class WHERE relnamespace='mobile_release'::regnamespace AND relkind IN ('r','S') LOOP
   IF r<>'mobile_release_owner' AND (has_table_privilege(r,t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
    OR has_any_column_privilege(r,t.oid,'SELECT,INSERT,UPDATE,REFERENCES')) THEN RAISE EXCEPTION 'Registry table/column exposure rejected'; END IF;
  END LOOP;
 END LOOP;
 FOR p IN SELECT oid,proowner,proacl FROM pg_proc WHERE pronamespace='mobile_release'::regnamespace
  OR oid='public.mobile_update_authorize(uuid)'::regprocedure LOOP
  IF p.proowner<>'mobile_release_owner'::regrole THEN RAISE EXCEPTION 'Wrong function owner'; END IF;
  IF EXISTS(SELECT FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE a.grantee NOT IN ('mobile_release_owner'::regrole,'mobile_release_publisher'::regrole,'mobile_release_reader'::regrole,'mobile_release_operator'::regrole,'mobile_release_registry_login'::regrole,'service_role'::regrole)) THEN RAISE EXCEPTION 'Unapproved function ACL'; END IF;
 END LOOP;
 IF has_function_privilege('service_role','mobile_release.allocate(text,text,text)','EXECUTE')
 OR has_function_privilege('mobile_release_registry_login','mobile_release.control(boolean,text)','EXECUTE')
 OR has_function_privilege('mobile_release_storage_publisher','public.mobile_update_authorize(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Cross-boundary EXECUTE rejected'; END IF;
 IF has_any_column_privilege('mobile_release_storage_publisher','storage.objects','UPDATE,REFERENCES')
 OR has_any_column_privilege('mobile_release_storage_publisher','storage.buckets','INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Storage column authority rejected'; END IF;
END $assert$;
