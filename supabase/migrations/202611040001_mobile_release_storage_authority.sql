-- CANDIDATE ONLY: isolated PG17 rehearsal; NOT approved for production install.
-- Native Storage custom JWT role authority only. No JWT/key issuance, bucket
-- creation, registry mutation, public delivery or exposed-schema changes.
-- Run with a reviewed administrator capable of CREATE ROLE / storage DDL.
-- Non-idempotent by design: refuse EVERY preexisting role, never adopt it.
BEGIN;
SET LOCAL search_path = pg_catalog;
DO $guard$
BEGIN
  IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
    RAISE EXCEPTION 'PostgreSQL 17 rehearsal required';
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname='mobile_release_storage_publisher') THEN
    RAISE EXCEPTION 'mobile_release_storage_publisher already exists; review identity separately';
  END IF;
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='storage' AND c.relname IN ('objects','buckets')
        AND c.relkind='r' AND c.relrowsecurity
        AND c.relowner='supabase_storage_admin'::regrole) <> 2 THEN
    RAISE EXCEPTION 'Expected Storage-owned objects/buckets with RLS enabled';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_index i
      JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
      WHERE i.indrelid='storage.objects'::regclass AND i.indisunique AND i.indisvalid
        AND i.indisready AND i.indpred IS NULL AND i.indexprs IS NULL
        AND i.indnkeyatts=2 AND i.indnatts=2
      GROUP BY i.indexrelid
      HAVING count(*) FILTER (WHERE a.attname IN ('bucket_id','name'))=2) THEN
    RAISE EXCEPTION 'Expected unconditional unique object key (bucket_id,name)';
  END IF;
  IF NOT EXISTS (SELECT FROM storage.buckets
      WHERE id='fireside-mobile-releases' AND public IS FALSE) THEN
    RAISE EXCEPTION 'Expected existing private bucket fireside-mobile-releases';
  END IF;
  -- PUBLIC privileges are inherited even by NOINHERIT roles. Refuse, do NOT
  -- revoke shared ACLs. Also inspect column ACLs, which table ACL checks miss.
  IF EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) a
      WHERE n.nspname='storage' AND a.grantee=0)
    OR EXISTS (SELECT FROM pg_attribute att JOIN pg_class c ON c.oid=att.attrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      CROSS JOIN LATERAL aclexplode(att.attacl) a
      WHERE n.nspname='storage' AND a.grantee=0)
    OR EXISTS (SELECT FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a
      WHERE n.nspname='storage' AND a.grantee=0 AND a.privilege_type='CREATE') THEN
    RAISE EXCEPTION 'Unsafe PUBLIC storage ACL; separate owner review required';
  END IF;
  -- Global and storage-local PUBLIC defaults would expose future Storage
  -- relations via the required USAGE. Refuse instead of editing site defaults.
  IF EXISTS (SELECT FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
      WHERE d.defaclnamespace IN (0,'storage'::regnamespace::oid)
        AND d.defaclobjtype IN ('r','S') AND a.grantee=0) THEN
    RAISE EXCEPTION 'Unsafe PUBLIC storage default privileges';
  END IF;
  -- USAGE would expose previously hidden PUBLIC-callable definer routines.
  IF EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE n.nspname='storage' AND p.prosecdef
        AND a.grantee=0 AND a.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'Unsafe PUBLIC storage SECURITY DEFINER routine';
  END IF;
END
$guard$;

CREATE ROLE mobile_release_storage_publisher
  NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
-- No outbound memberships, no object ownership, no function wrappers. In
-- particular: never inherit anon/authenticated/service_role/storage owner.
GRANT USAGE ON SCHEMA storage TO mobile_release_storage_publisher;
GRANT SELECT, INSERT ON storage.objects TO mobile_release_storage_publisher;
GRANT SELECT ON storage.buckets TO mobile_release_storage_publisher;

-- Restrictive fences prevent a permissive PUBLIC policy from broadening bucket
-- scope. Existing shared ACLs/policies are intentionally left intact.
CREATE POLICY mobile_release_storage_object_fence ON storage.objects
  AS RESTRICTIVE FOR ALL TO mobile_release_storage_publisher
  USING (bucket_id='fireside-mobile-releases')
  WITH CHECK (bucket_id='fireside-mobile-releases');
CREATE POLICY mobile_release_storage_object_read ON storage.objects
  FOR SELECT TO mobile_release_storage_publisher
  USING (bucket_id='fireside-mobile-releases');
CREATE POLICY mobile_release_storage_object_create ON storage.objects
  FOR INSERT TO mobile_release_storage_publisher
  WITH CHECK (bucket_id='fireside-mobile-releases');
CREATE POLICY mobile_release_storage_no_update ON storage.objects
  AS RESTRICTIVE FOR UPDATE TO mobile_release_storage_publisher
  USING (false) WITH CHECK (false);
CREATE POLICY mobile_release_storage_no_delete ON storage.objects
  AS RESTRICTIVE FOR DELETE TO mobile_release_storage_publisher USING (false);
CREATE POLICY mobile_release_storage_bucket_fence ON storage.buckets
  AS RESTRICTIVE FOR ALL TO mobile_release_storage_publisher
  USING (id='fireside-mobile-releases' AND public IS FALSE)
  WITH CHECK (false);
CREATE POLICY mobile_release_storage_bucket_read ON storage.buckets
  FOR SELECT TO mobile_release_storage_publisher
  USING (id='fireside-mobile-releases' AND public IS FALSE);

-- Transport prerequisite, not credential issuance. The deployed Storage login
-- has SET-capable, non-inherited authenticator membership. Explicit PG17 grant
-- lets that trusted backend SET LOCAL ROLE to the JWT's custom role. It does not
-- let the custom role SET ROLE back to authenticator or to privileged roles.
GRANT mobile_release_storage_publisher TO authenticator
  WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;

-- No tables/sequences/functions are created, so site ALTER DEFAULT PRIVILEGES
-- cannot leak new candidate-owned objects. Never modify global/shared defaults
-- or grant ALL TABLES / future objects. Existing defaults remain byte-for-byte.
DO $assert$
BEGIN
  IF EXISTS (SELECT FROM pg_auth_members WHERE member='mobile_release_storage_publisher'::regrole)
    OR EXISTS (SELECT FROM pg_class WHERE relowner='mobile_release_storage_publisher'::regrole)
    OR has_schema_privilege('mobile_release_storage_publisher','storage','CREATE')
    OR has_table_privilege('mobile_release_storage_publisher','storage.objects',
         'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
    OR has_table_privilege('mobile_release_storage_publisher','storage.buckets',
         'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') THEN
    RAISE EXCEPTION 'Unexpected effective publisher authority';
  END IF;
END
$assert$;
COMMIT;
