-- Execute inside the same transaction as the frozen bundle. Never adopt roles.
SET LOCAL search_path=pg_catalog;
SELECT pg_advisory_xact_lock(687340040001);
DO $guard$
BEGIN
 IF current_setting('server_version_num')::integer/10000 <> 17 THEN RAISE EXCEPTION 'PG17 required'; END IF;
 IF EXISTS(SELECT FROM pg_roles WHERE rolname IN ('mobile_release_owner','mobile_release_publisher','mobile_release_reader','mobile_release_operator','mobile_release_registry_login','mobile_release_storage_publisher'))
 OR to_regnamespace('mobile_release') IS NOT NULL
 OR to_regprocedure('public.mobile_update_authorize(uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'Existing mobile identity/object: manual recovery review required';
 END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='service_role' AND NOT rolcanlogin)
 OR NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticator' AND NOT rolsuper AND NOT rolbypassrls) THEN
  RAISE EXCEPTION 'Unexpected transport role';
 END IF;
 IF NOT EXISTS(SELECT FROM pg_class WHERE oid='auth.users'::regclass AND relrowsecurity)
 OR NOT EXISTS(SELECT FROM pg_class WHERE oid='fireside_pi.personal_information'::regclass AND relrowsecurity) THEN
  RAISE EXCEPTION 'Identity base relation RLS required';
 END IF;
 -- New schema USAGE must not unlock existing PUBLIC-definer authority.
 IF EXISTS(SELECT FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE p.pronamespace IN ('auth'::regnamespace,'fireside_pi'::regnamespace)
 AND p.prosecdef AND a.grantee=0 AND a.privilege_type='EXECUTE') THEN
  RAISE EXCEPTION 'PUBLIC identity definer requires separate owner review';
 END IF;
 IF EXISTS(SELECT FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
 WHERE d.defaclnamespace IN (0,'storage'::regnamespace) AND d.defaclobjtype IN ('r','S') AND a.grantee=0) THEN
  RAISE EXCEPTION 'Unsafe PUBLIC defaults';
 END IF;
END $guard$;
