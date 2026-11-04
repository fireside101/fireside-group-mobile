"""Opt-in real PostgreSQL tests. Never reads dotenv; refuses other database/socket."""
import json
import os
from pathlib import Path
import threading
import re
import uuid
import unittest
from concurrent.futures import ThreadPoolExecutor

DSN = os.environ.get('MOBILE_TEST_DSN')

class IsolatedConnection:
    def __init__(self, conn, schema): self.raw, self.schema = conn, schema
    def execute(self, sql, *args):
        return self.raw.execute(re.sub(r'\bmobile_release\b', self.schema, sql), *args)
    def close(self): self.raw.close()


@unittest.skipUnless(DSN, 'isolated PostgreSQL DSN not explicitly provided')
class RegistrySQLTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        cls.pg = psycopg
        cls.schema = 'mobile_test_' + uuid.uuid4().hex
        cls.conn = IsolatedConnection(psycopg.connect(DSN, autocommit=True), cls.schema)
        cls.addClassCleanup(cls.conn.close)
        cls.addClassCleanup(lambda: cls.conn.execute('drop schema if exists mobile_release cascade'))
        row = cls.conn.execute("select current_database(), inet_server_addr(), current_setting('port'), current_setting('server_version')").fetchone()
        if row != ('mobile_rehearsal', None, '55479', '17.6'):
            raise RuntimeError('isolated PostgreSQL identity mismatch')
        if cls.conn.raw.info.host != '/home/nderitu/.hermes/cache/scratch/unified-attendance-pg17':
            raise RuntimeError('isolated socket mismatch')
        if cls.conn.execute("select to_regnamespace('mobile_release')").fetchone()[0]:
            raise RuntimeError('existing mobile schema: refuse destructive test setup')
        sql = Path(__file__).resolve().parents[2] / 'supabase/migrations/202611030001_mobile_release.sql'
        if not sql.exists(): raise AssertionError('scoped registry migration not implemented')
        source = sql.read_text()
        # Existing shared fixture roles are prerequisites, never provisioned here.
        roles = cls.conn.execute("select count(*) from pg_roles where rolname in ('mobile_release_owner','mobile_release_publisher','mobile_release_reader','mobile_release_operator')").fetchone()[0]
        if roles != 4: raise RuntimeError('shared rehearsal roles unavailable')
        source = source[:source.index('DO $$ BEGIN')] + source[source.index('CREATE SCHEMA mobile_release'):]
        cls.conn.execute(source)
    @classmethod
    def tearDownClass(cls):
        pass  # registered cleanups also run on partial setup failure
    def setUp(self):
        self.conn.execute('truncate mobile_release.artifacts, mobile_release.plans, mobile_release.app cascade')
        self.conn.execute("insert into mobile_release.app values (true, 5, repeat('a',64), false, null, 'https://approved.example/mobile')")
    def call(self, sql, args=(), role='mobile_release_publisher'):
        with self.pg.connect(DSN) as conn:
            conn.execute('set local role ' + role)
            return conn.execute(re.sub(r'\bmobile_release\b', self.schema, sql), args).fetchone()[0]
    def reserve(self, code=6, commit='b'*40):
        return self.call('select mobile_release.reserve(%s,%s,%s,%s)', (commit, f'1.0.{code-1}', code, 'a'*64))
    def payload(self, code=6, commit='b'*40):
        return dict(package='com.firesideafrica.firesidegroup', version_code=code,
            version_name=f'1.0.{code-1}', commit=commit, tag=f'v1.0.{code-1}', signer_sha256='a'*64,
            sha256='c'*64, size=42,
            object_key=f"com.firesideafrica.firesidegroup/{code}/{commit}/{'c'*64}.apk",
            apk_url=f"https://approved.example/mobile/com.firesideafrica.firesidegroup/{code}/{commit}/{'c'*64}.apk")
    def advertise(self, payload):
        return self.call('select mobile_release.advertise(%s::jsonb)', (json.dumps(payload),))
    def test_allocate_before_build_monotonic_commit_idempotent(self):
        def allocate(c):
            return self.call('select mobile_release.allocate(%s,%s,%s)', (c, '1.0.4', 'a'*64))
        first = allocate('b'*40)
        self.assertEqual(first, {'code':6, 'version_name':'1.0.6'})
        self.assertEqual(allocate('b'*40), first)
        with ThreadPoolExecutor(4) as pool:
            plans = list(pool.map(allocate, [hex(i)[2:]*40 for i in range(12,16)]))
        self.assertEqual(sorted(p['code'] for p in plans), [7,8,9,10])
        self.assertEqual(allocate('b'*40), first)

    def test_publisher_session_lock_serializes_cloud_finalization(self):
        import mobile_release as r
        registry = r.PostgresRegistry(DSN, schema=self.schema)
        with self.pg.connect(DSN, autocommit=True) as other:
            with registry.publication_lock():
                self.assertFalse(other.execute('select pg_try_advisory_lock(721434875)').fetchone()[0])
            self.assertTrue(other.execute('select pg_try_advisory_lock(721434875)').fetchone()[0])
            other.execute('select pg_advisory_unlock(721434875)')

    def test_allocator_fail_closed_for_unseeded_paused_and_invalid_signer(self):
        sql = 'select mobile_release.allocate(%s,%s,%s)'
        for args in [('b'*40,'1.0.4','f'*64),('x'*40,'1.0.4','a'*64),('b'*40,None,'a'*64)]:
            with self.assertRaises(self.pg.Error): self.call(sql,args)
        self.conn.execute('update mobile_release.app set paused=true')
        with self.assertRaises(self.pg.Error): self.call(sql,('b'*40,'1.0.4','a'*64))
        self.conn.execute('truncate mobile_release.app cascade')
        with self.assertRaises(self.pg.Error): self.call(sql,('b'*40,'1.0.4','a'*64))

    def test_unseeded_or_paused_registry_holds_planning(self):
        self.conn.execute('truncate mobile_release.app cascade')
        with self.assertRaises(self.pg.Error): self.reserve()
        self.conn.execute("insert into mobile_release.app values (true,5,repeat('a',64),true,null,'https://approved.example/mobile')")
        with self.assertRaises(self.pg.Error): self.reserve()

    def test_immutable_records_reject_even_owner_edit(self):
        self.reserve(); self.advertise(self.payload())
        for sql in ["update mobile_release.artifacts set payload='{}'", 'delete from mobile_release.plans']:
            with self.assertRaises(self.pg.Error): self.conn.execute(sql)

    def test_monotonic_plan_and_idempotent_reservation(self):
        self.assertEqual(self.reserve(), 6)
        self.assertEqual(self.reserve(), 6)
        for args in [(5, 'd'*40), (6, 'd'*40), (7, 'b'*40)]:
            with self.assertRaises(self.pg.Error): self.reserve(*args)
    def test_atomic_concurrent_same_code_only_one_source_wins(self):
        gate = threading.Barrier(2)
        def worker(commit):
            gate.wait()
            try: self.reserve(commit=commit); return 'ok'
            except self.pg.Error: return 'held'
        with ThreadPoolExecutor(2) as pool:
            self.assertEqual(sorted(pool.map(worker, ['b'*40, 'd'*40])), ['held', 'ok'])
    def test_concurrent_same_source_is_idempotent(self):
        with ThreadPoolExecutor(4) as pool:
            self.assertEqual(list(pool.map(lambda _: self.reserve(), range(4))), [6]*4)
    def test_advertise_immutable_readback_and_no_rollback(self):
        self.reserve(); p = self.payload()
        self.assertEqual(self.advertise(p), p)
        self.assertEqual(self.advertise(p), p)
        self.reserve(7, 'd'*40); newer = self.payload(7, 'd'*40); self.advertise(newer)
        self.assertEqual(self.advertise(p), p)  # receipt only, never repoint old version
        self.assertEqual(self.call('select mobile_release.latest()', role='mobile_release_reader'), newer)
        changed = dict(p, size=43)
        with self.assertRaises(self.pg.Error): self.advertise(changed)
    def test_late_old_advertisement_refused(self):
        self.reserve(); self.reserve(7, 'd'*40); self.advertise(self.payload(7, 'd'*40))
        with self.assertRaises(self.pg.Error): self.advertise(self.payload())
    def test_pause_revoke_do_not_reappear_on_retry(self):
        self.reserve(); p = self.payload(); self.advertise(p)
        self.call('select mobile_release.control(%s,%s)', (True, None), role='mobile_release_operator')
        self.assertIsNone(self.call('select mobile_release.latest()', role='mobile_release_reader'))
        self.call('select mobile_release.control(%s,%s)', (False, 'b'*40), role='mobile_release_operator')
        with self.assertRaises(self.pg.Error): self.advertise(p)
        self.assertIsNone(self.call('select mobile_release.latest()', role='mobile_release_reader'))
    def test_reader_cannot_write_or_read_private_tables(self):
        for sql in ["select mobile_release.reserve(repeat('b',40),'1.0.5',6,repeat('a',64))",
                    'select * from mobile_release.artifacts',
                    'update mobile_release.app set floor=0',
                    'select mobile_release.control(false,null)']:
            with self.assertRaises(self.pg.Error): self.call(sql, role='mobile_release_reader')
    def test_publisher_cannot_mutate_tables_or_control(self):
        for sql in ['delete from mobile_release.artifacts', 'update mobile_release.app set floor=0',
                    'select mobile_release.control(false,null)', 'create table mobile_release.evil(x int)']:
            with self.assertRaises(self.pg.Error): self.call(sql)
    def test_package_signer_metadata_validation(self):
        with self.assertRaises(self.pg.Error):
            self.call("select mobile_release.reserve(repeat('b',40),'1.0.5',6,repeat('d',64))")
        self.reserve()
        for field, value in [('package', 'other'), ('sha256', ''), ('version_code', True),
                             ('signer_sha256', 'd'*64), ('apk_url', 'http://evil'), ('object_key', 'other')]:
            with self.subTest(field=field):
                with self.assertRaises(self.pg.Error): self.advertise(dict(self.payload(), **{field:value}))
    def test_production_registry_environment_requires_tls_not_local_test_dsn(self):
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        import mobile_release as release
        env = {'MOBILE_REGISTRY_CONTRACT':'mobile_release_v1', 'MOBILE_REGISTRY_DSN':DSN}
        with self.assertRaises(release.Held): release.PostgresRegistry.from_environment(env)
        env['MOBILE_REGISTRY_DSN'] = 'host=registry.example dbname=synthetic user=publisher sslmode=verify-full sslrootcert=/approved/ca.pem'
        self.assertIsInstance(release.PostgresRegistry.from_environment(env), release.PostgresRegistry)

    def test_python_publisher_against_real_scoped_sql_adapter(self):
        # Exercise effective publisher ACLs without creating/changing shared roles.
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        import mobile_release as release
        from test_mobile_release import Github, Storage, APK
        class Publisher(release.PostgresRegistry):
            def call(inner, sql, args): return self.call(sql, args)
        registry = Publisher(DSN, schema=self.schema)
        spec = release.Spec('1.0.5', 6, 'b'*40, 'a'*64)
        events = []
        storage = Storage(events)
        args = (spec, APK, {}, Github(events), storage, registry,
                lambda *args: None, 'https://approved.example/mobile')
        first = release.publish(*args)
        self.assertEqual(first, release.publish(*args))
        self.assertEqual(first, self.call('select mobile_release.latest()', role='mobile_release_reader'))
        self.assertEqual(len(storage.objects), 1)

    def test_parallel_advertisement_never_regresses(self):
        self.reserve(); self.reserve(7, 'd'*40)
        def worker(payload):
            try: return self.advertise(payload)
            except self.pg.Error: return None
        with ThreadPoolExecutor(2) as pool:
            list(pool.map(worker, [self.payload(), self.payload(7, 'd'*40)]))
        self.assertEqual(self.call('select mobile_release.latest()', role='mobile_release_reader')['version_code'], 7)
