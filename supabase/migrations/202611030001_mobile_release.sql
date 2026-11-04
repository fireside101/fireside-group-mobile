-- CANDIDATE / isolated rehearsal only. No production installation approval.
-- No Warehouse/public/Calvary objects. No Supabase role grants or exposed-schema changes.
-- Fail if schema already exists: never silently adopt unknown objects.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='mobile_release_owner') THEN CREATE ROLE mobile_release_owner NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='mobile_release_publisher') THEN CREATE ROLE mobile_release_publisher NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='mobile_release_reader') THEN CREATE ROLE mobile_release_reader NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='mobile_release_operator') THEN CREATE ROLE mobile_release_operator NOLOGIN; END IF;
END $$;
CREATE SCHEMA mobile_release AUTHORIZATION mobile_release_owner;
SET LOCAL ROLE mobile_release_owner;
REVOKE ALL ON SCHEMA mobile_release FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA mobile_release REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA mobile_release REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Intentionally UNSEEDED: verified fleet floor, signer and approved storage are owner gates.
CREATE TABLE mobile_release.app (
 singleton boolean PRIMARY KEY CHECK(singleton),
 floor integer NOT NULL CHECK(floor>0 AND floor<=2100000000),
 signer text NOT NULL CHECK(signer ~ '^[0-9a-f]{64}$'),
 paused boolean NOT NULL DEFAULT true,
 advertised_commit text,
 storage_base text NOT NULL CHECK(storage_base ~ '^https://[^/?#@:]+(/[^?#]*)?$' AND right(storage_base,1)<>'/')
);
CREATE TABLE mobile_release.plans (
 commit text PRIMARY KEY CHECK(commit ~ '^[0-9a-f]{40}$'),
 version_name text NOT NULL UNIQUE CHECK(version_name ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
 code integer NOT NULL UNIQUE CHECK(code>0 AND code<=2100000000),
 signer text NOT NULL CHECK(signer ~ '^[0-9a-f]{64}$'),
 planned_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 planned_by name NOT NULL DEFAULT session_user
);
CREATE TABLE mobile_release.artifacts (
 commit text PRIMARY KEY REFERENCES mobile_release.plans(commit),
 payload jsonb NOT NULL,
 published_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 published_by name NOT NULL DEFAULT session_user
);
CREATE TABLE mobile_release.revocations (
 commit text PRIMARY KEY REFERENCES mobile_release.artifacts(commit),
 revoked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 revoked_by name NOT NULL DEFAULT session_user
);
ALTER TABLE mobile_release.app ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_release.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_release.artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_release.revocations ENABLE ROW LEVEL SECURITY;
-- Defense in depth: even owner-path accidental edits cannot rewrite artifact evidence.
CREATE FUNCTION mobile_release.immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable release evidence'; END $$;
CREATE TRIGGER artifacts_immutable BEFORE UPDATE OR DELETE ON mobile_release.artifacts
 FOR EACH ROW EXECUTE FUNCTION mobile_release.immutable();
CREATE TRIGGER plans_immutable BEFORE UPDATE OR DELETE ON mobile_release.plans
 FOR EACH ROW EXECUTE FUNCTION mobile_release.immutable();
CREATE TRIGGER revocations_immutable BEFORE UPDATE OR DELETE ON mobile_release.revocations
 FOR EACH ROW EXECUTE FUNCTION mobile_release.immutable();

CREATE FUNCTION mobile_release.reserve(c text, v text, n integer, s text) RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
DECLARE a mobile_release.app; p mobile_release.plans;
BEGIN
 SELECT * INTO STRICT a FROM mobile_release.app WHERE singleton FOR UPDATE;
 IF a.paused OR s IS DISTINCT FROM a.signer THEN RAISE EXCEPTION 'release admission held'; END IF;
 SELECT * INTO p FROM mobile_release.plans WHERE commit=c;
 IF FOUND THEN
  IF p.version_name IS DISTINCT FROM v OR p.code IS DISTINCT FROM n OR p.signer IS DISTINCT FROM s
   THEN RAISE EXCEPTION 'source reservation conflict'; END IF;
  RETURN p.code;
 END IF;
 IF n IS NULL OR n <= greatest(a.floor, coalesce((SELECT max(code) FROM mobile_release.plans),0))
  THEN RAISE EXCEPTION 'versionCode must exceed all reserved codes and verified floor'; END IF;
 INSERT INTO mobile_release.plans(commit,version_name,code,signer) VALUES(c,v,n,s);
 RETURN n;
END $$;

-- Allocate BEFORE building/signing. Failed plans consume codes; retries reuse the
-- original commit plan, even after later commits have allocated higher codes.
CREATE FUNCTION mobile_release.allocate(c text, base text, s text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
DECLARE a mobile_release.app; p mobile_release.plans; n integer; v text; patch bigint;
BEGIN
 SELECT * INTO STRICT a FROM mobile_release.app WHERE singleton FOR UPDATE;
 IF a.paused OR s IS DISTINCT FROM a.signer OR base !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
   OR c !~ '^[0-9a-f]{40}$' OR base IS NULL OR c IS NULL
 THEN RAISE EXCEPTION 'allocation admission held'; END IF;
 SELECT * INTO p FROM mobile_release.plans WHERE commit=c;
 IF FOUND THEN
   IF p.signer IS DISTINCT FROM s THEN RAISE EXCEPTION 'source signer conflict'; END IF;
   RETURN jsonb_build_object('code',p.code,'version_name',p.version_name);
 END IF;
 IF greatest(a.floor, coalesce((SELECT max(code) FROM mobile_release.plans),0)) >= 2100000000
 THEN RAISE EXCEPTION 'versionCode exhausted'; END IF;
 n := greatest(a.floor, coalesce((SELECT max(code) FROM mobile_release.plans),0)) + 1;
 patch := greatest(split_part(base,'.',3)::bigint,n);
 v := split_part(base,'.',1)||'.'||split_part(base,'.',2)||'.'||patch;
 WHILE EXISTS(SELECT FROM mobile_release.plans WHERE version_name=v) LOOP
   patch := patch + 1;
   v := split_part(base,'.',1)||'.'||split_part(base,'.',2)||'.'||patch;
 END LOOP;
 PERFORM mobile_release.reserve(c,v,n,s);
 RETURN jsonb_build_object('code',n,'version_name',v);
END $$;

CREATE FUNCTION mobile_release.advertise(x jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
DECLARE a mobile_release.app; p mobile_release.plans; old jsonb; key text;
BEGIN
 SELECT * INTO STRICT a FROM mobile_release.app WHERE singleton FOR UPDATE;
 IF a.paused THEN RAISE EXCEPTION 'publication paused'; END IF;
 SELECT * INTO STRICT p FROM mobile_release.plans WHERE commit=x->>'commit';
 IF EXISTS(SELECT FROM mobile_release.revocations WHERE commit=p.commit) THEN RAISE EXCEPTION 'release revoked'; END IF;
 IF jsonb_typeof(x)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(x))<>10
  OR x - ARRAY['package','version_code','version_name','commit','tag','signer_sha256','sha256','size','object_key','apk_url'] <> '{}'::jsonb
  OR x->>'package' IS DISTINCT FROM 'com.firesideafrica.firesidegroup'
  OR x->'version_code' IS DISTINCT FROM to_jsonb(p.code)
  OR x->>'version_name' IS DISTINCT FROM p.version_name
  OR x->>'tag' IS DISTINCT FROM 'v'||p.version_name
  OR x->>'signer_sha256' IS DISTINCT FROM a.signer
  OR x->>'signer_sha256' IS DISTINCT FROM p.signer
  OR coalesce(x->>'sha256','') !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(x->'size') IS DISTINCT FROM 'number'
  OR coalesce(x->>'size','') !~ '^[1-9][0-9]*$'
  THEN RAISE EXCEPTION 'invalid release payload'; END IF;
 key := 'com.firesideafrica.firesidegroup/'||p.code||'/'||p.commit||'/'||(x->>'sha256')||'.apk';
 IF x->>'object_key' IS DISTINCT FROM key OR x->>'apk_url' IS DISTINCT FROM a.storage_base||'/'||key
  THEN RAISE EXCEPTION 'storage scope mismatch'; END IF;
 SELECT payload INTO old FROM mobile_release.artifacts WHERE commit=p.commit;
 IF FOUND THEN
  IF old IS DISTINCT FROM x THEN RAISE EXCEPTION 'immutable artifact conflict'; END IF;
  RETURN old; -- idempotent receipt, never repoint older artifact
 END IF;
 IF p.code <= a.floor THEN RAISE EXCEPTION 'stale advertisement'; END IF;
 INSERT INTO mobile_release.artifacts(commit,payload) VALUES(p.commit,x);
 UPDATE mobile_release.app SET floor=p.code,advertised_commit=p.commit WHERE singleton;
 RETURN x;
END $$;
CREATE FUNCTION mobile_release.receipt(c text) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
 SELECT payload FROM mobile_release.artifacts WHERE commit=c
$$;
CREATE FUNCTION mobile_release.latest() RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
 SELECT r.payload FROM mobile_release.app a JOIN mobile_release.artifacts r ON r.commit=a.advertised_commit
 WHERE NOT a.paused AND NOT EXISTS(SELECT FROM mobile_release.revocations v WHERE v.commit=r.commit)
$$;
CREATE FUNCTION mobile_release.control(pause boolean, revoke_commit text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,mobile_release AS $$
BEGIN
 PERFORM 1 FROM mobile_release.app WHERE singleton FOR UPDATE;
 IF pause IS NULL THEN RAISE EXCEPTION 'explicit pause required'; END IF;
 IF revoke_commit IS NOT NULL THEN
  INSERT INTO mobile_release.revocations(commit) VALUES(revoke_commit) ON CONFLICT DO NOTHING;
 END IF;
 UPDATE mobile_release.app SET paused=pause WHERE singleton;
 RETURN true;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA mobile_release FROM PUBLIC,mobile_release_publisher,mobile_release_reader,mobile_release_operator;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA mobile_release FROM PUBLIC,mobile_release_publisher,mobile_release_reader,mobile_release_operator;
GRANT USAGE ON SCHEMA mobile_release TO mobile_release_publisher,mobile_release_reader,mobile_release_operator;
GRANT EXECUTE ON FUNCTION mobile_release.reserve(text,text,integer,text), mobile_release.advertise(jsonb),mobile_release.receipt(text) TO mobile_release_publisher;
GRANT EXECUTE ON FUNCTION mobile_release.latest() TO mobile_release_reader,mobile_release_publisher;
GRANT EXECUTE ON FUNCTION mobile_release.allocate(text,text,text) TO mobile_release_publisher;
GRANT EXECUTE ON FUNCTION mobile_release.control(boolean,text) TO mobile_release_operator;
COMMIT;
