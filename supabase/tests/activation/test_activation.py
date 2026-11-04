"""Activation PG17 integration: owns disposable clusters, never shared 55479."""
import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from typing import Any

ROOT = Path(__file__).resolve().parents[3]

def load(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    assert spec is not None and spec.loader is not None
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

activation=load('activation',ROOT/'supabase/activation/activate.py')
fixture=load('authority',ROOT/'supabase/tests/mobile_storage_authority/test_authority.py')
IDENTITY='''CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz,is_anonymous boolean,banned_until timestamptz,deleted_at timestamptz);
CREATE SCHEMA fireside_pi; CREATE TABLE fireside_pi.personal_information(staff_email text,active boolean,deleted_at timestamptz,resignation_date date);
ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY; ALTER TABLE fireside_pi.personal_information ENABLE ROW LEVEL SECURITY;'''

class CombinedSQL(unittest.TestCase):
    def setUp(self):
        self.pg=fixture.AuthorityTest('runTest'); self.pg.setUp()
        self.addCleanup(self.pg.doCleanups)
        self.sql=self.pg.sql
        self.sql(IDENTITY)

    def install(self,ok=True):
        return self.pg.command('psql',input='BEGIN;'+activation.combined()+'COMMIT;',ok=ok)

    def verify(self):
        self.sql((activation.HERE/'verify.sql').read_text())

    def test_combined_paused_seed_owned_functions_private_acl(self):
        self.install(); self.verify()
        self.assertEqual(self.sql('SELECT floor,signer,paused,advertised_commit FROM mobile_release.app').strip(),'5|701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9|t|')
        self.assertEqual(self.sql('SELECT mobile_release.latest()',user='mobile_release_registry_login').strip(),'')
        for text in ["SELECT mobile_release.allocate('"+'b'*40+"','1.0.4','701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9')",'SELECT * FROM mobile_release.app','SELECT mobile_release.control(false,null)','SET ROLE service_role','SET ROLE mobile_release_owner','UPDATE auth.users SET email=null']:
            self.assertNotEqual(self.pg.command('psql',input=text,user='mobile_release_registry_login',ok=False).returncode,0,text)
        self.assertEqual(self.pg.scoped('SELECT count(*) FROM storage.objects').strip(),'0')
        self.pg.scoped("INSERT INTO storage.objects(bucket_id,name) VALUES('fireside-mobile-releases','activation.apk')")
        self.pg.denied("UPDATE storage.objects SET name='bad'")
        self.pg.denied("INSERT INTO storage.objects(bucket_id,name) VALUES('other-bucket','bad')")
        self.assertNotEqual(self.pg.command('psql',input='SET ROLE authenticated; SELECT public.mobile_update_authorize(null)',ok=False).returncode,0)

    def test_preexisting_role_refuses_without_adoption(self):
        for role in ['mobile_release_owner','mobile_release_registry_login','mobile_release_publisher','mobile_release_storage_publisher']:
            with self.subTest(role=role):
                self.sql(f'CREATE ROLE {role} LOGIN BYPASSRLS; GRANT service_role TO {role}')
                self.assertNotEqual(self.install(ok=False).returncode,0)
                self.assertEqual(self.sql("SELECT to_regnamespace('mobile_release') IS NULL").strip(),'t')
                self.sql(f'DROP ROLE {role}')

    def test_poisoned_defaults_on_installer_cannot_leak_functions(self):
        # Fixture already has global non-PUBLIC defaults. Public-schema ones match live.
        self.sql('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon,authenticated,remote_app')
        self.install(); self.verify()
        self.assertEqual(self.sql("SELECT has_function_privilege('remote_app','public.mobile_update_authorize(uuid)','EXECUTE')").strip(),'f')

    def test_public_column_defaults_and_definer_fail_atomic(self):
        for poison,undo in [
            ('GRANT SELECT(name) ON storage.objects TO PUBLIC','REVOKE SELECT(name) ON storage.objects FROM PUBLIC'),
            ('ALTER DEFAULT PRIVILEGES GRANT SELECT ON TABLES TO PUBLIC','ALTER DEFAULT PRIVILEGES REVOKE SELECT ON TABLES FROM PUBLIC'),
            ("CREATE FUNCTION auth.unsafe() RETURNS int LANGUAGE sql SECURITY DEFINER AS 'SELECT 1'",'DROP FUNCTION auth.unsafe()'),
            ('CREATE POLICY mobile_release_storage_object_read ON storage.objects FOR SELECT TO anon USING(false)','DROP POLICY mobile_release_storage_object_read ON storage.objects')]:
            with self.subTest(poison=poison):
                self.sql(poison)
                self.assertNotEqual(self.install(ok=False).returncode,0)
                self.assertEqual(self.sql("SELECT count(*) FROM pg_roles WHERE rolname LIKE 'mobile_release_%'").strip(),'0')
                self.sql(undo)

    def test_readback_rejects_column_membership_owner_and_execute_drift(self):
        self.install()
        for poison in ['GRANT UPDATE(floor) ON mobile_release.app TO mobile_release_registry_login',
                       'GRANT UPDATE(name) ON storage.objects TO mobile_release_storage_publisher',
                       'GRANT service_role TO mobile_release_registry_login WITH INHERIT FALSE,SET TRUE',
                       'ALTER FUNCTION mobile_release.advertise(jsonb) OWNER TO postgres',
                       'ALTER POLICY mobile_release_storage_object_fence ON storage.objects USING(true) WITH CHECK(true)',
                       'ALTER TABLE storage.objects DISABLE ROW LEVEL SECURITY',
                       'GRANT EXECUTE ON FUNCTION mobile_release.control(boolean,text) TO mobile_release_registry_login']:
            with self.subTest(poison=poison):
                result=self.pg.command('psql',input='BEGIN;'+poison+';'+(activation.HERE/'verify.sql').read_text()+'ROLLBACK;',ok=False)
                self.assertNotEqual(result.returncode,0)
        self.verify()

    def test_private_publication_and_identity_flow(self):
        self.install()
        # Explicit isolated activation only, never part of production installer.
        self.sql('SET ROLE mobile_release_operator; SELECT mobile_release.control(false,null); RESET ROLE;')
        signer='701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9'
        plan=json.loads(self.sql(f"SELECT mobile_release.allocate('{'b'*40}','1.0.4','{signer}')::text",user='mobile_release_registry_login'))
        self.assertEqual(plan,dict(code=6,version_name='1.0.6'))
        artifact=dict(package='com.firesideafrica.firesidegroup',version_code=6,version_name='1.0.6',tag='v1.0.6',commit='b'*40,signer_sha256=signer,sha256='c'*64,size=58983786,provider='supabase-rest',bucket='fireside-mobile-releases',object_key=f"com.firesideafrica.firesidegroup/6/{'b'*40}/{'c'*64}.apk")
        self.sql("SELECT mobile_release.advertise('"+json.dumps(artifact)+"')",user='mobile_release_registry_login')
        self.sql("INSERT INTO auth.users VALUES('11111111-1111-4111-8111-111111111111','staff@example.test',now(),false,null,null); INSERT INTO fireside_pi.personal_information VALUES('staff@example.test',true,null,null)")
        result=self.sql("SET ROLE service_role; SELECT public.mobile_update_authorize('11111111-1111-4111-8111-111111111111')::text")
        self.assertEqual(json.loads(result),artifact)
        self.sql('UPDATE fireside_pi.personal_information SET active=false')
        self.assertNotEqual(self.pg.command('psql',input="SET ROLE service_role; SELECT public.mobile_update_authorize('11111111-1111-4111-8111-111111111111')",ok=False).returncode,0)

class CredentialTests(unittest.TestCase):
    def test_finite_scoped_jwt_and_scram(self):
        token=activation.jwt_token('synthetic-test-secret-not-production'*2,100)
        payload=json.loads(base64.urlsafe_b64decode(token.split('.')[1]+'=='))
        self.assertEqual(payload['exp']-payload['iat'],3600)
        self.assertEqual(payload['role'],'mobile_release_storage_publisher')
        self.assertNotIn('service_role',token)
        value=activation.scram('synthetic-password')
        self.assertTrue(value.startswith('SCRAM-SHA-256$4096:'))
        self.assertNotIn('synthetic-password',value)

    def test_secure_input_fd_and_target_refusal(self):
        with tempfile.TemporaryFile(dir=fixture.SCRATCH,mode='w+') as f:
            os.fchmod(f.fileno(),0o600)
            json.dump(dict(owner_dsn='private',jwt_secret='x'*40),f);f.flush();f.seek(0)
            self.assertEqual(activation.private_input(f.fileno())['owner_dsn'],'private')
            os.fchmod(f.fileno(),0o644)
            with self.assertRaises(ValueError):activation.private_input(f.fileno())
        with patch.dict(os.environ,{},clear=True):
            for dsn in ['host=localhost sslmode=disable','host=supabase.firesideafrica.cloud port=5433 dbname=postgres sslmode=require','service=prod']:
                with self.assertRaises(ValueError):activation.owner_options(dsn)

class TLSWrapper(unittest.TestCase):
    pg: Any
    sql: Any
    setUp = CombinedSQL.setUp
    # Only the transport-target admission is substituted. The operator's real
    # run() executes its exact SQL, SCRAM rotation, login/readback and private IO.
    def test_real_wrapper_tls_scram_refresh_and_private_outputs(self):
        import contextlib
        import io
        import socket
        import psycopg
        from psycopg.conninfo import conninfo_to_dict, make_conninfo
        pg=self.pg
        cert=pg.base/'server.crt'; key=pg.base/'server.key'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
            '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost',
            '-keyout',str(key),'-out',str(cert)],check=True,capture_output=True)
        os.chmod(key,0o600)
        import secrets
        owner_password = secrets.token_hex(24)
        self.sql("ALTER ROLE postgres PASSWORD '" + owner_password + "'")
        pg.command('pg_ctl','-D',str(pg.data),'-m','fast','-w','stop')
        (pg.data/'pg_hba.conf').write_text('local all all trust\nhostssl all all 127.0.0.1/32 scram-sha-256\n')
        with socket.socket() as s:
            s.bind(('127.0.0.1',0));port=s.getsockname()[1]
        pg.env['PGPORT']=str(port)
        pg.command('pg_ctl','-D',str(pg.data),'-l',str(pg.base/'postgres.log'),'-o',
            f'-k {pg.sock} -p {port} -c listen_addresses=127.0.0.1 -c unix_socket_permissions=0700 -c ssl=on -c ssl_cert_file={cert} -c ssl_key_file={key}','-w','start')
        info=dict(host='localhost',port=str(port),dbname='authority_rehearsal',user='postgres',
                  password=owner_password,sslmode='verify-full',sslrootcert=str(cert),connect_timeout=3)
        # The fixed run() expects postgres: bootstrap the same synthetic tables
        # in this cluster's empty postgres DB. Roles are cluster-wide already.
        pg.env['PGDATABASE']='postgres'
        bootstrap=fixture.BOOTSTRAP[fixture.BOOTSTRAP.index('CREATE SCHEMA storage'):]
        self.sql(bootstrap);self.sql(IDENTITY)
        info['dbname']='postgres'
        outputs=[]
        for action in ['install-paused','refresh']:
            out=pg.base/('private-'+action)
            buf=io.StringIO()
            with patch.object(activation,'private_input',return_value=dict(owner_dsn='never-printed',jwt_secret='synthetic-signing-secret'*3)), patch.object(activation,'owner_options',return_value=info), contextlib.redirect_stdout(buf):
                activation.run(argparse.Namespace(action=action,output=str(out)))
            data=json.loads((out/'publisher.json').read_text());outputs.append(data)
            self.assertNotIn('synthetic',buf.getvalue())
            self.assertEqual((out.stat().st_mode & 0o777),0o700)
            self.assertEqual(((out/'publisher.json').stat().st_mode & 0o777),0o600)
            self.assertNotIn('jwt_secret',data)
            dsn=data['MOBILE_REGISTRY_DSN']
            with psycopg.connect(dsn) as c:
                row=c.execute('SELECT current_user').fetchone()
                assert row is not None
                self.assertEqual(row[0],'mobile_release_registry_login')
            bad=conninfo_to_dict(dsn);bad['password']='wrong'
            with self.assertRaises(psycopg.OperationalError):psycopg.connect(make_conninfo(**bad))
            bad=conninfo_to_dict(dsn);bad['host']='127.0.0.1'
            with self.assertRaises(psycopg.OperationalError):psycopg.connect(make_conninfo(**bad))
        self.assertNotEqual(outputs[0]['MOBILE_REGISTRY_DSN'],outputs[1]['MOBILE_REGISTRY_DSN'])
        with self.assertRaises(psycopg.OperationalError):psycopg.connect(outputs[0]['MOBILE_REGISTRY_DSN'])
        for output in outputs:
            raw_password=conninfo_to_dict(output['MOBILE_REGISTRY_DSN'])['password']
            self.assertNotIn(raw_password,(pg.base/'postgres.log').read_text())
        self.sql("ALTER ROLE mobile_release_registry_login VALID UNTIL '2000-01-01'")
        with self.assertRaises(psycopg.OperationalError):psycopg.connect(outputs[1]['MOBILE_REGISTRY_DSN'])

if __name__=='__main__':unittest.main(verbosity=2)
