-- LOCAL CANDIDATE ONLY. Not an automatic migration, not deployed.
-- Requires the reviewed mobile_release v1 schema; replaces its advertisement
-- contract only after an owner-approved coordinated publisher/client cutover.
BEGIN;
CREATE OR REPLACE FUNCTION mobile_release.advertise(x jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
DECLARE a mobile_release.app; p mobile_release.plans; old jsonb; key text;
BEGIN
 SELECT * INTO STRICT a FROM mobile_release.app WHERE singleton FOR UPDATE;
 IF a.paused THEN RAISE EXCEPTION 'publication paused'; END IF;
 SELECT * INTO STRICT p FROM mobile_release.plans WHERE commit=x->>'commit';
 IF EXISTS(SELECT FROM mobile_release.revocations WHERE commit=p.commit) THEN RAISE EXCEPTION 'release revoked'; END IF;
 IF jsonb_typeof(x) IS DISTINCT FROM 'object'
  OR (SELECT count(*) FROM jsonb_object_keys(x))<>11
  OR x - ARRAY['package','version_code','version_name','commit','tag','signer_sha256','sha256','size','provider','bucket','object_key'] <> '{}'::jsonb
  OR x->>'package' IS DISTINCT FROM 'com.firesideafrica.firesidegroup'
  OR x->'version_code' IS DISTINCT FROM to_jsonb(p.code)
  OR x->>'version_name' IS DISTINCT FROM p.version_name
  OR x->>'tag' IS DISTINCT FROM 'v'||p.version_name
  OR x->>'signer_sha256' IS DISTINCT FROM a.signer
  OR x->>'signer_sha256' IS DISTINCT FROM p.signer
  OR coalesce(x->>'sha256','') !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(x->'size') IS DISTINCT FROM 'number'
  OR coalesce(x->>'size','') !~ '^[1-9][0-9]*$'
  OR (x->>'size')::numeric > 536870912
  OR x->>'provider' IS DISTINCT FROM 'supabase-rest'
  OR x->>'bucket' IS DISTINCT FROM 'fireside-mobile-releases'
 THEN RAISE EXCEPTION 'invalid private release payload'; END IF;
 key := 'com.firesideafrica.firesidegroup/'||p.code||'/'||p.commit||'/'||(x->>'sha256')||'.apk';
 IF x->>'object_key' IS DISTINCT FROM key THEN RAISE EXCEPTION 'storage scope mismatch'; END IF;
 SELECT payload INTO old FROM mobile_release.artifacts WHERE commit=p.commit;
 IF FOUND THEN
  IF old IS DISTINCT FROM x THEN RAISE EXCEPTION 'immutable artifact conflict'; END IF;
  RETURN old;
 END IF;
 IF p.code <= a.floor THEN RAISE EXCEPTION 'stale advertisement'; END IF;
 INSERT INTO mobile_release.artifacts(commit,payload) VALUES(p.commit,x);
 UPDATE mobile_release.app SET floor=p.code,advertised_commit=p.commit WHERE singleton;
 RETURN x;
END $$;
ALTER FUNCTION mobile_release.advertise(jsonb) OWNER TO mobile_release_owner;

-- Authoritative relations/column types discovered read-only through catalog.
-- Never trust employee IDs, email, role, PI ID or user_metadata from the caller.
-- Email must be current and verified in actual auth.users. Count ALL matching PI
-- rows before lifecycle filtering: deleted/inactive duplicates are ambiguous too.
GRANT USAGE ON SCHEMA auth,fireside_pi TO mobile_release_owner;
GRANT SELECT(id,email,email_confirmed_at,is_anonymous,banned_until,deleted_at)
 ON auth.users TO mobile_release_owner;
GRANT SELECT(staff_email,active,deleted_at,resignation_date)
 ON fireside_pi.personal_information TO mobile_release_owner;
-- Both live base relations have RLS enabled. This server-only role needs all
-- matches (including inactive/deleted duplicates), but only the columns above.
-- No BYPASSRLS or employee-role policy is granted. Owner approval required.
CREATE POLICY mobile_release_identity_read ON auth.users FOR SELECT
 TO mobile_release_owner USING (true);
CREATE POLICY mobile_release_eligibility_read ON fireside_pi.personal_information FOR SELECT
 TO mobile_release_owner USING (true);
CREATE FUNCTION public.mobile_update_authorize(subject uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
DECLARE verified_email text; matches bigint; eligible bigint; result jsonb;
BEGIN
 SELECT lower(btrim(u.email)) INTO verified_email FROM auth.users u
 WHERE u.id=subject AND u.email_confirmed_at IS NOT NULL
 AND u.is_anonymous IS FALSE AND u.deleted_at IS NULL
 AND (u.banned_until IS NULL OR u.banned_until <= statement_timestamp());
 IF verified_email IS NULL OR verified_email='' THEN RAISE EXCEPTION 'not eligible' USING ERRCODE='42501'; END IF;
 -- Reject conflicting actual Auth accounts too, rather than choose first.
 IF (SELECT count(*) FROM auth.users u WHERE lower(btrim(u.email))=verified_email)<>1
 THEN RAISE EXCEPTION 'not eligible' USING ERRCODE='42501'; END IF;
 SELECT count(*),count(*) FILTER (WHERE p.active IS TRUE AND p.deleted_at IS NULL
   AND (p.resignation_date IS NULL OR p.resignation_date > current_date))
 INTO matches,eligible FROM fireside_pi.personal_information p WHERE lower(btrim(p.staff_email))=verified_email;
 IF matches<>1 OR eligible<>1 THEN RAISE EXCEPTION 'not eligible' USING ERRCODE='42501'; END IF;
 result := mobile_release.latest();
 -- Fail closed on old public artifacts until coordinated publisher cutover.
 IF result IS NOT NULL AND (result->>'provider' IS DISTINCT FROM 'supabase-rest'
   OR result->>'bucket' IS DISTINCT FROM 'fireside-mobile-releases' OR result ? 'apk_url')
 THEN RAISE EXCEPTION 'private contract unavailable'; END IF;
 RETURN result;
END $$;
ALTER FUNCTION public.mobile_update_authorize(uuid) OWNER TO mobile_release_owner;
-- Remove creator default ACLs too, not just implicit PUBLIC. No employee or
-- anonymous caller may pass someone else's subject to this server-only RPC.
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT DISTINCT grantee FROM aclexplode((SELECT proacl FROM pg_proc
   WHERE oid='public.mobile_update_authorize(uuid)'::regprocedure))
 WHERE grantee<>(SELECT oid FROM pg_roles WHERE rolname='mobile_release_owner') LOOP
   IF r.grantee=0 THEN REVOKE ALL ON FUNCTION public.mobile_update_authorize(uuid) FROM PUBLIC;
   ELSE EXECUTE format('REVOKE ALL ON FUNCTION public.mobile_update_authorize(uuid) FROM %I',pg_get_userbyid(r.grantee)); END IF;
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.mobile_update_authorize(uuid) TO service_role;
COMMIT;
