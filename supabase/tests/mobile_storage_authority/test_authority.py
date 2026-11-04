"""Disposable PG17 authority rehearsal. No dotenv, network DB, JWT or production IO."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from unittest.mock import patch

import psycopg

ROOT = Path(__file__).resolve().parents[3]
CANDIDATE = ROOT / 'supabase/migrations/202611040001_mobile_release_storage_authority.sql'
PG_BIN = Path(os.environ.get('MOBILE_AUTHORITY_PG_BIN', '/home/nderitu/.hermes/cache/scratch/unified-attendance-pg17/pgsql/bin'))
SCRATCH = Path('/home/nderitu/.hermes/cache/scratch')
ROLE = 'mobile_release_storage_publisher'

BOOTSTRAP = """
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE ROLE remote_app NOLOGIN;
CREATE ROLE "NDERITU" NOLOGIN;
CREATE ROLE authenticator LOGIN NOINHERIT;
CREATE ROLE supabase_storage_admin LOGIN NOINHERIT;
GRANT anon, authenticated, service_role TO authenticator WITH INHERIT FALSE;
GRANT authenticator TO supabase_storage_admin WITH INHERIT FALSE;
CREATE SCHEMA storage AUTHORIZATION supabase_storage_admin;
GRANT USAGE ON SCHEMA storage TO anon,authenticated,service_role,remote_app,"NDERITU";
SET ROLE supabase_storage_admin;
CREATE TABLE storage.buckets (
 id text PRIMARY KEY, name text NOT NULL, owner uuid, owner_id text,
 public boolean DEFAULT false, file_size_limit bigint, allowed_mime_types text[]
);
CREATE TABLE storage.objects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text REFERENCES storage.buckets(id),
 name text, owner uuid, owner_id text, metadata jsonb, user_metadata jsonb, version text,
 created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(),
 UNIQUE(bucket_id,name)
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
-- Actual live catalog ACL shape: public-user roles already have broad table
-- privileges, but no membership is granted from those roles to the candidate.
GRANT ALL ON storage.objects,storage.buckets TO anon,authenticated,service_role,"NDERITU";
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects,storage.buckets TO remote_app;
GRANT ALL ON storage.objects,storage.buckets TO postgres WITH GRANT OPTION;
RESET ROLE;
INSERT INTO storage.buckets(id,name,public) VALUES
 ('fireside-mobile-releases','fireside-mobile-releases',false),('other-bucket','other-bucket',false);
INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES
 ('other-bucket','hidden.apk','someone-else','{"bytes":"other"}');
-- Relevant live policies: unrelated roles must not become publisher ancestors.
CREATE POLICY calvary_app_releases_read ON storage.objects FOR SELECT TO anon,authenticated
 USING(bucket_id='calvary-app-releases');
CREATE POLICY ict_upload_attachments ON storage.objects FOR INSERT TO anon,authenticated
 WITH CHECK(bucket_id='ict-attachments');
-- Match site defaults, then poison global defaults as a regression: candidate
-- must create no tables/functions/sequences that inherit these grants.
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES GRANT ALL ON TABLES TO remote_app,anon,authenticated;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO anon,authenticated,remote_app;
"""


class AuthorityTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='mobile-storage-authority-pg17-', dir=SCRATCH)
        self.base = Path(self.tmp.name)
        self.sock = self.base / 'sock'
        self.sock.mkdir(mode=0o700)
        self.data = self.base / 'data'
        # Fixed private endpoint; never inspect/use/start the parent's shared data.
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.base), 'LC_ALL': 'C',
                    'PGHOST': str(self.sock), 'PGPORT': '55439', 'PGUSER': 'postgres',
                    'PGDATABASE': 'authority_rehearsal', 'PGCONNECT_TIMEOUT': '3'}
        self.command('initdb', '-D', str(self.data), '-U', 'postgres', '-A', 'trust', '--no-locale', '--encoding=UTF8')
        self.command('pg_ctl', '-D', str(self.data), '-l', str(self.base / 'postgres.log'),
                     '-o', f"-k {self.sock} -p 55439 -c listen_addresses='' -c unix_socket_permissions=0700", '-w', 'start')
        self.addCleanup(self.cleanup_pg)
        self.command('psql', '-d', 'postgres', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
                     input="CREATE DATABASE authority_rehearsal TEMPLATE template0 ENCODING 'UTF8';")
        self.sql(BOOTSTRAP)
        self.assertEqual(self.sql("SHOW server_version_num").strip()[:2], '17')
        self.assertEqual(self.sql('SHOW data_directory').strip(), str(self.data))
        self.assertEqual(self.sql('SHOW listen_addresses').strip(), '')

    def cleanup_pg(self):
        self.command('pg_ctl', '-D', str(self.data), '-m', 'fast', '-w', 'stop')
        self.tmp.cleanup()

    def command(self, executable, *args, input=None, user=None, ok=True):
        env = dict(self.env)
        if user:
            env['PGUSER'] = user
        if executable == 'psql':
            # psycopg binary supplies libpq; this PG build has server binaries only.
            database = args[args.index('-d') + 1] if '-d' in args else env['PGDATABASE']
            try:
                with patch.dict(os.environ, env, clear=True), psycopg.connect(
                        host=env['PGHOST'], port=env['PGPORT'], user=env['PGUSER'],
                        dbname=database, connect_timeout=3, autocommit=True) as conn:
                    with conn.cursor() as cur:
                        cur.execute((input or '').replace('\\set VERBOSITY verbose\n', ''))
                        rows = []
                        while True:
                            if cur.description:
                                rows.extend('|'.join('' if v is None else ('t' if v is True else 'f' if v is False else str(v)) for v in row) for row in cur.fetchall())
                            if not cur.nextset():
                                break
                        result = subprocess.CompletedProcess(args, 0, '\n'.join(rows) + ('\n' if rows else ''), '')
            except psycopg.Error as exc:
                result = subprocess.CompletedProcess(args, 1, '', f'{exc.sqlstate}: {exc}')
        else:
            result = subprocess.run([str(PG_BIN / executable), *args], env=env, input=input,
                                    text=True, capture_output=True, timeout=30)
        if ok and result.returncode:
            self.fail(result.stdout + result.stderr)
        return result

    def sql(self, text, user=None):
        return self.command('psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', input=text, user=user).stdout

    def install(self, ok=True):
        self.assertTrue(CANDIDATE.exists(), 'candidate authority migration missing')
        return self.command('psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
                            input=CANDIDATE.read_text(), ok=ok)

    def scoped(self, text, user='supabase_storage_admin'):
        return self.sql(f"BEGIN; SET LOCAL ROLE {ROLE}; " + text + '; COMMIT;', user=user)

    def denied(self, text, state='42501', user='supabase_storage_admin'):
        result = self.command('psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
            input=f"\\set VERBOSITY verbose\nBEGIN; SET LOCAL ROLE {ROLE}; {text}; COMMIT;", user=user, ok=False)
        self.assertNotEqual(result.returncode, 0, text)
        self.assertIn(state, result.stderr, result.stderr)

    def test_create_read_only_bucket_no_replace(self):
        self.install()
        # Actual database LOGIN -> transitive SET ROLE, not owner-side queries.
        self.assertEqual(self.scoped('SELECT session_user,current_user').strip(),
                         'supabase_storage_admin|' + ROLE)
        self.assertEqual(self.scoped("SELECT id FROM storage.buckets").strip(), 'fireside-mobile-releases')
        # Storage createObject writes owner(uuid when UUID sub), owner_id(text sub),
        # metadata/user_metadata/version; it does not require auth.users membership.
        self.scoped("""INSERT INTO storage.objects(bucket_id,name,owner,owner_id,metadata,user_metadata,version)
          VALUES('fireside-mobile-releases','first.apk','00000000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8000-000000000001','{"bytes":"original"}','{}','v1') RETURNING name""")
        self.assertEqual(self.scoped("SELECT name,metadata->>'bytes' FROM storage.objects").strip(), 'first.apk|original')
        self.denied("INSERT INTO storage.objects(bucket_id,name) VALUES('other-bucket','no.apk')")
        self.denied("INSERT INTO storage.objects(bucket_id,name) VALUES(NULL,'no.apk')")
        self.denied("INSERT INTO storage.objects(bucket_id,name) VALUES('fireside-mobile-releases','first.apk')", '23505')
        for statement in [
            "UPDATE storage.objects SET metadata='{}' WHERE name='first.apk'",
            "DELETE FROM storage.objects WHERE name='first.apk'",
            "TRUNCATE storage.objects",
            "INSERT INTO storage.objects(bucket_id,name) VALUES('fireside-mobile-releases','first.apk') ON CONFLICT(bucket_id,name) DO UPDATE SET metadata='{}'",
            "INSERT INTO storage.buckets(id,name) VALUES('new','new')",
            "UPDATE storage.buckets SET public=true",
            "DELETE FROM storage.buckets",
            "CREATE TABLE storage.surprise(id int)",
        ]:
            with self.subTest(statement=statement):
                self.denied(statement)
        self.assertEqual(self.sql("SELECT metadata->>'bytes' FROM storage.objects WHERE name='first.apk'").strip(), 'original')
        self.assertEqual(self.scoped("SELECT count(*) FROM storage.objects WHERE bucket_id='other-bucket'").strip(), '0')
        self.assertEqual(self.scoped("SELECT count(*) FROM storage.buckets WHERE id='other-bucket'").strip(), '0')

    def test_catalog_and_runtime_no_inherited_authority(self):
        before = self.sql("SELECT nspacl::text FROM pg_namespace WHERE nspname='storage'; SELECT defaclacl::text FROM pg_default_acl ORDER BY oid")
        self.install()
        self.assertEqual(self.sql("SELECT defaclacl::text FROM pg_default_acl ORDER BY oid"), before.split('\n',1)[1])
        self.assertEqual(self.sql(f"SELECT rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolinherit OR rolreplication FROM pg_roles WHERE rolname='{ROLE}'").strip(), 'f')
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_auth_members WHERE member='{ROLE}'::regrole").strip(), '0')
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_class WHERE relowner='{ROLE}'::regrole").strip(), '0')
        self.assertEqual(self.sql(f"SELECT has_table_privilege('{ROLE}','storage.objects','SELECT,INSERT'), has_table_privilege('{ROLE}','storage.objects','UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')").strip(), 't|f')
        self.sql(f"CREATE ROLE isolated_publisher_login LOGIN NOINHERIT; GRANT {ROLE} TO isolated_publisher_login WITH INHERIT FALSE, SET TRUE;")
        self.assertEqual(self.scoped('SELECT current_user', user='isolated_publisher_login').strip(), ROLE)
        for target in ['supabase_storage_admin','authenticator','service_role','authenticated','anon','postgres']:
            self.denied(f'SET ROLE {target}', user='isolated_publisher_login')
        # Defaults must not leak callable helper objects or later table rights.
        self.sql('CREATE TABLE storage.future_table(secret text); INSERT INTO storage.future_table VALUES(\'hidden\');')
        self.denied('SELECT * FROM storage.future_table')
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_proc WHERE proowner='{ROLE}'::regrole").strip(), '0')
        self.sql('DROP ROLE isolated_publisher_login')
        self.assertEqual(self.sql(f"SELECT member::regrole,admin_option,inherit_option,set_option FROM pg_auth_members WHERE roleid='{ROLE}'::regrole").strip(), 'authenticator|f|f|t')

    def test_no_anon_or_authenticated_release_access(self):
        old_acl = self.sql("SELECT c.relname,a.grantee::regrole,a.privilege_type,a.is_grantable FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE c.oid IN ('storage.objects'::regclass,'storage.buckets'::regclass) ORDER BY 1,2,3")
        old_functions = self.sql("SELECT oid,proacl FROM pg_proc WHERE pronamespace='storage'::regnamespace ORDER BY oid")
        self.install()
        self.assertEqual(self.sql(f"SELECT c.relname,a.grantee::regrole,a.privilege_type,a.is_grantable FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE c.oid IN ('storage.objects'::regclass,'storage.buckets'::regclass) AND a.grantee<>'{ROLE}'::regrole ORDER BY 1,2,3"), old_acl)
        self.assertEqual(self.sql("SELECT oid,proacl FROM pg_proc WHERE pronamespace='storage'::regnamespace ORDER BY oid"), old_functions)
        self.scoped("INSERT INTO storage.objects(bucket_id,name) VALUES('fireside-mobile-releases','private.apk')")
        for target in ['anon', 'authenticated']:
            self.assertEqual(self.sql(f"BEGIN; SET LOCAL ROLE {target}; SELECT count(*) FROM storage.objects WHERE bucket_id='fireside-mobile-releases'; COMMIT", user='authenticator').strip(), '0')
            denied = self.command('psql', input=f"BEGIN; SET LOCAL ROLE {target}; INSERT INTO storage.objects(bucket_id,name) VALUES('fireside-mobile-releases','forbidden.apk'); COMMIT", user='authenticator', ok=False)
            self.assertNotEqual(denied.returncode, 0)
            self.assertIn('42501', denied.stderr)

    def test_missing_immutable_unique_key_refused(self):
        self.sql('ALTER TABLE storage.objects DROP CONSTRAINT objects_bucket_id_name_key')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unique object key', result.stderr)

    def test_policy_collision_rolls_back_everything(self):
        self.sql('CREATE POLICY mobile_release_storage_object_fence ON storage.objects FOR SELECT TO anon USING(false)')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_roles WHERE rolname='{ROLE}'").strip(), '0')

    def test_non_superuser_installer_implicit_admin_is_not_runtime_inheritance(self):
        self.sql('CREATE ROLE candidate_installer LOGIN CREATEROLE INHERIT; GRANT supabase_storage_admin TO candidate_installer;')
        self.assertTrue(CANDIDATE.exists())
        result = self.command('psql', input=CANDIDATE.read_text(), user='candidate_installer', ok=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        # PG17 adds creator ADMIN TRUE / INHERIT FALSE / SET FALSE automatically.
        # This is an incoming administrator edge, never an outbound owner grant.
        self.assertEqual(self.sql(f"SELECT member::regrole,admin_option,inherit_option,set_option FROM pg_auth_members WHERE roleid='{ROLE}'::regrole ORDER BY member::regrole::text").strip(), 'authenticator|f|f|t\ncandidate_installer|t|f|f')
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_auth_members WHERE member='{ROLE}'::regrole").strip(), '0')

    def test_public_column_grant_refused(self):
        self.sql('GRANT SELECT(name) ON storage.objects TO PUBLIC')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('PUBLIC storage', result.stderr)

    def test_public_definer_routine_refused(self):
        self.sql("CREATE FUNCTION storage.unsafe() RETURNS void LANGUAGE sql SECURITY DEFINER AS 'DELETE FROM storage.objects';")
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SECURITY DEFINER', result.stderr)

    def test_public_table_defaults_refused(self):
        self.sql('ALTER DEFAULT PRIVILEGES GRANT SELECT ON TABLES TO PUBLIC')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('PUBLIC storage default', result.stderr)

    def test_preexisting_role_refused_even_if_unprivileged(self):
        self.sql(f'CREATE ROLE {ROLE} NOLOGIN')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already exists', result.stderr)
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_auth_members WHERE roleid='{ROLE}'::regrole").strip(), '0')

    def test_preexisting_unsafe_role_refused(self):
        self.sql(f'CREATE ROLE {ROLE} LOGIN BYPASSRLS; GRANT service_role TO {ROLE}')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already exists', result.stderr)

    def test_public_grant_refused_without_revoking_existing_acl(self):
        self.sql('GRANT SELECT,INSERT,UPDATE ON storage.objects TO PUBLIC')
        before = self.sql("SELECT relacl::text FROM pg_class WHERE oid='storage.objects'::regclass")
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('PUBLIC storage', result.stderr)
        self.assertEqual(self.sql("SELECT relacl::text FROM pg_class WHERE oid='storage.objects'::regclass"), before)
        self.assertEqual(self.sql(f"SELECT count(*) FROM pg_roles WHERE rolname='{ROLE}'").strip(), '0')

    def test_rls_disabled_refused(self):
        self.sql('ALTER TABLE storage.objects DISABLE ROW LEVEL SECURITY')
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('RLS', result.stderr)

    def test_public_bucket_refused(self):
        self.sql("UPDATE storage.buckets SET public=true WHERE id='fireside-mobile-releases'")
        result = self.install(ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('private bucket', result.stderr)

    def test_restrictive_fence_survives_unrelated_public_policy(self):
        self.install()
        self.sql('CREATE POLICY future_public_read ON storage.objects FOR SELECT TO PUBLIC USING(true); CREATE POLICY future_public_insert ON storage.objects FOR INSERT TO PUBLIC WITH CHECK(true);')
        self.assertEqual(self.scoped('SELECT count(*) FROM storage.objects').strip(), '0')
        self.denied("INSERT INTO storage.objects(bucket_id,name) VALUES('other-bucket','no.apk')")


if __name__ == '__main__':
    unittest.main(verbosity=2)
