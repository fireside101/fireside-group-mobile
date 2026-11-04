"""Real disposable PG17: synthetic Auth/PI, no production credentials or network."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('authority_fixture', ROOT / 'supabase/tests/mobile_storage_authority/test_authority.py')
assert spec is not None and spec.loader is not None
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
SUBJECT = '11111111-1111-4111-8111-111111111111'
C = 'b' * 40
H = 'c' * 64
S = 'a' * 64
A = dict(package='com.firesideafrica.firesidegroup', version_code=7, version_name='1.0.7', tag='v1.0.7', commit=C,
         signer_sha256=S, sha256=H, size=3, provider='supabase-rest', bucket='fireside-mobile-releases',
         object_key=f'com.firesideafrica.firesidegroup/7/{C}/{H}.apk')

class PrivateDeliverySQL(unittest.TestCase):
    def setUp(self):
        self.pg = fixture.AuthorityTest('runTest')
        self.pg.setUp()
        self.addCleanup(self.pg.doCleanups)
        self.sql = self.pg.sql
        self.sql('''CREATE SCHEMA auth; CREATE TABLE auth.users (
          id uuid PRIMARY KEY, email text, email_confirmed_at timestamptz,
          is_anonymous boolean, banned_until timestamptz, deleted_at timestamptz);
          CREATE SCHEMA fireside_pi; CREATE TABLE fireside_pi.personal_information (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(), staff_email text,
          active boolean, deleted_at timestamptz, resignation_date date);
        ''')
        self.sql('ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY; ALTER TABLE fireside_pi.personal_information ENABLE ROW LEVEL SECURITY; REVOKE ALL ON auth.users,fireside_pi.personal_information FROM anon,authenticated,remote_app;')
        self.sql((ROOT / 'supabase/migrations/202611030001_mobile_release.sql').read_text())
        candidate = ROOT / 'supabase/candidates/mobile_private_delivery.sql'
        self.assertTrue(candidate.exists(), 'private delivery candidate missing')
        self.sql(candidate.read_text())
        self.sql(f"INSERT INTO auth.users VALUES ('{SUBJECT}','staff@example.test',now(),false,null,null); INSERT INTO fireside_pi.personal_information(staff_email,active) VALUES('STAFF@example.test',true);")
        self.sql(f"INSERT INTO mobile_release.app(singleton,floor,signer,paused,storage_base) VALUES(true,6,'{S}',false,'https://unused.invalid'); SELECT mobile_release.reserve('{C}','1.0.7',7,'{S}');")
        self.advertise(A)

    def advertise(self, value):
        return self.sql("SET ROLE mobile_release_publisher; SELECT mobile_release.advertise('" + json.dumps(value) + "'::jsonb); RESET ROLE;")

    def authorize(self):
        out = self.sql(f"SET ROLE service_role; SELECT public.mobile_update_authorize('{SUBJECT}')::text; RESET ROLE;")
        return json.loads(out.strip()) if out.strip() else None

    def test_eligible_and_stable_private_receipt(self):
        self.assertEqual(self.authorize(), A)
        self.advertise(A)
        self.assertEqual(self.authorize(), A)

    def test_inactive_deleted_missing_ambiguous_identity(self):
        for change in ["UPDATE fireside_pi.personal_information SET active=false",
                       "UPDATE fireside_pi.personal_information SET deleted_at=now()",
                       "UPDATE fireside_pi.personal_information SET resignation_date=current_date",
                       "INSERT INTO fireside_pi.personal_information(staff_email,active) VALUES('staff@example.test',true)",
                       "UPDATE auth.users SET email_confirmed_at=null",
                       "UPDATE auth.users SET banned_until=now()+interval '1 day'",
                       "UPDATE auth.users SET deleted_at=now()",
                       "UPDATE auth.users SET is_anonymous=true",
                       "INSERT INTO auth.users VALUES(gen_random_uuid(),'staff@example.test',now(),false,null,null)",
                       "UPDATE auth.users SET email='unmapped@example.test'"]:
            with self.subTest(change=change):
                result = self.pg.command('psql',input=f"BEGIN; {change}; SET LOCAL ROLE service_role; SELECT public.mobile_update_authorize('{SUBJECT}');",ok=False)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('42501',result.stderr)

    def test_paused_and_revoked_return_no_release(self):
        self.sql('UPDATE mobile_release.app SET paused=true')
        self.assertIsNone(self.authorize())
        self.sql(f"UPDATE mobile_release.app SET paused=false; INSERT INTO mobile_release.revocations(commit) VALUES('{C}')")
        self.assertIsNone(self.authorize())

    def test_no_phone_role_authority_or_directory_grants(self):
        for role in ['anon','authenticated','remote_app']:
            self.assertEqual(self.sql(f"SELECT has_function_privilege('{role}','public.mobile_update_authorize(uuid)','EXECUTE')").strip(),'f')
            self.assertEqual(self.sql(f"SELECT has_table_privilege('{role}','fireside_pi.personal_information','SELECT')").strip(),'f')
        result=self.pg.command('psql',input=f"SET ROLE authenticated; SELECT public.mobile_update_authorize('{SUBJECT}')",ok=False)
        self.assertNotEqual(result.returncode,0)

    def test_reject_public_url_changed_bucket_hash_size_and_extra_keys(self):
        for patch in [dict(apk_url='https://public.invalid/7.apk'),dict(bucket='other'),dict(size=True),dict(size=536870913),dict(object_key='../7.apk'),dict(provider='s3'),dict(sha256='0'*64)]:
            with self.subTest(patch=patch):
                payload=json.dumps({**A,**patch})
                result=self.pg.command('psql',input="SET ROLE mobile_release_publisher; SELECT mobile_release.advertise('"+payload+"'::jsonb)",ok=False)
                self.assertNotEqual(result.returncode,0)

if __name__ == '__main__':
    unittest.main()
