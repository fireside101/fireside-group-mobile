-- Read-only, reusable admission before credential rotation and after commit.
DO $verify$
DECLARE r record; p record; role_name text; allowed boolean; actual boolean;
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE oid IN ('storage.objects'::regclass,'storage.buckets'::regclass) AND relrowsecurity AND relowner='supabase_storage_admin'::regrole)<>2 THEN RAISE EXCEPTION 'Storage owner/RLS drift'; END IF;
 IF NOT EXISTS(SELECT FROM pg_auth_members WHERE member='authenticator'::regrole AND roleid='mobile_release_storage_publisher'::regrole AND NOT admin_option AND NOT inherit_option AND set_option) THEN RAISE EXCEPTION 'Transport membership drift'; END IF;
 IF EXISTS(
  WITH expected(name,cmd,permissive,qual,check_expr) AS (VALUES
   ('mobile_release_storage_bucket_fence','*',false,'((id = ''fireside-mobile-releases''::text) AND (public IS FALSE))','false'),
   ('mobile_release_storage_bucket_read','r',true,'((id = ''fireside-mobile-releases''::text) AND (public IS FALSE))',NULL),
   ('mobile_release_storage_no_delete','d',false,'false',NULL),
   ('mobile_release_storage_no_update','w',false,'false','false'),
   ('mobile_release_storage_object_create','a',true,NULL,'(bucket_id = ''fireside-mobile-releases''::text)'),
   ('mobile_release_storage_object_fence','*',false,'(bucket_id = ''fireside-mobile-releases''::text)','(bucket_id = ''fireside-mobile-releases''::text)'),
   ('mobile_release_storage_object_read','r',true,'(bucket_id = ''fireside-mobile-releases''::text)',NULL))
  SELECT FROM expected e LEFT JOIN pg_policy policy ON policy.polname=e.name AND policy.polrelid=CASE WHEN e.name LIKE '%bucket_%' THEN 'storage.buckets'::regclass ELSE 'storage.objects'::regclass END
  WHERE policy.oid IS NULL OR policy.polcmd::text<>e.cmd OR policy.polpermissive<>e.permissive
   OR pg_get_expr(policy.polqual,policy.polrelid) IS DISTINCT FROM e.qual
   OR pg_get_expr(policy.polwithcheck,policy.polrelid) IS DISTINCT FROM e.check_expr
   OR policy.polroles<>ARRAY['mobile_release_storage_publisher'::regrole::oid]
 ) THEN RAISE EXCEPTION 'Storage policy drift'; END IF;
 IF EXISTS(SELECT FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname IN ('storage','auth','fireside_pi','mobile_release') AND a.grantee=0 AND a.privilege_type='CREATE') THEN RAISE EXCEPTION 'PUBLIC CREATE drift'; END IF;
 IF EXISTS(SELECT FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a WHERE d.defaclnamespace IN (0,'storage'::regnamespace) AND d.defaclobjtype IN ('r','S') AND a.grantee=0) THEN RAISE EXCEPTION 'PUBLIC defaults drift'; END IF;
 IF NOT EXISTS(SELECT FROM mobile_release.app WHERE singleton AND floor>=5 AND signer='701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9') THEN RAISE EXCEPTION 'Seed drift'; END IF;
 FOR r IN SELECT * FROM pg_roles WHERE rolname IN ('mobile_release_owner','mobile_release_publisher','mobile_release_reader','mobile_release_operator','mobile_release_registry_login','mobile_release_storage_publisher') LOOP
  IF r.rolsuper OR r.rolinherit OR r.rolcreaterole OR r.rolcreatedb OR r.rolreplication OR r.rolbypassrls OR (r.rolcanlogin IS DISTINCT FROM (r.rolname='mobile_release_registry_login')) THEN RAISE EXCEPTION 'Role attributes drift'; END IF;
  IF EXISTS(SELECT FROM pg_auth_members WHERE member=r.oid) THEN RAISE EXCEPTION 'Outbound membership drift'; END IF;
  IF r.rolname<>'mobile_release_owner' THEN
   IF EXISTS(SELECT FROM pg_class WHERE relowner=r.oid) OR EXISTS(SELECT FROM pg_proc WHERE proowner=r.oid) OR EXISTS(SELECT FROM pg_namespace WHERE nspowner=r.oid) THEN RAISE EXCEPTION 'Runtime ownership drift'; END IF;
   IF has_schema_privilege(r.oid,'mobile_release','CREATE') THEN RAISE EXCEPTION 'Schema privilege drift'; END IF;
   FOR p IN SELECT oid FROM pg_class WHERE relnamespace='mobile_release'::regnamespace AND relkind='r' LOOP
    IF has_table_privilege(r.oid,p.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') OR has_any_column_privilege(r.oid,p.oid,'SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Table/column privilege drift'; END IF;
   END LOOP;
  END IF;
 END LOOP;
 IF (SELECT count(*) FROM pg_roles WHERE rolname IN ('mobile_release_owner','mobile_release_publisher','mobile_release_reader','mobile_release_operator','mobile_release_registry_login','mobile_release_storage_publisher'))<>6 THEN RAISE EXCEPTION 'Missing role'; END IF;
 FOR p IN SELECT oid,proname,proowner,proacl FROM pg_proc WHERE pronamespace='mobile_release'::regnamespace OR oid='public.mobile_update_authorize(uuid)'::regprocedure LOOP
  IF p.proowner<>'mobile_release_owner'::regrole THEN RAISE EXCEPTION 'Function owner drift'; END IF;
  IF EXISTS(SELECT FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee NOT IN ('mobile_release_owner'::regrole,'mobile_release_publisher'::regrole,'mobile_release_reader'::regrole,'mobile_release_operator'::regrole,'mobile_release_registry_login'::regrole,'service_role'::regrole)) THEN RAISE EXCEPTION 'Unknown executor'; END IF;
  FOREACH role_name IN ARRAY ARRAY['mobile_release_registry_login','mobile_release_publisher','mobile_release_reader','mobile_release_operator','mobile_release_storage_publisher','anon','authenticated','service_role'] LOOP
   allowed := (role_name IN ('mobile_release_registry_login','mobile_release_publisher') AND p.proname IN ('allocate','reserve','advertise','receipt','latest'))
    OR (role_name='mobile_release_reader' AND p.proname='latest')
    OR (role_name='mobile_release_operator' AND p.proname='control')
    OR (role_name='service_role' AND p.proname='mobile_update_authorize');
   actual := has_function_privilege(role_name,p.oid,'EXECUTE');
   IF actual IS DISTINCT FROM allowed THEN RAISE EXCEPTION 'Executor matrix drift'; END IF;
  END LOOP;
 END LOOP;
 IF has_table_privilege('mobile_release_storage_publisher','storage.objects','UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
 OR has_any_column_privilege('mobile_release_storage_publisher','storage.objects','UPDATE,REFERENCES')
 OR has_table_privilege('mobile_release_storage_publisher','storage.buckets','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
 OR has_any_column_privilege('mobile_release_storage_publisher','storage.buckets','INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Storage privilege drift'; END IF;
END $verify$;
