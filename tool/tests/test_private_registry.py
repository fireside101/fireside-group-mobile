"""Real isolated PostgreSQL private advertisement + loopback object publication."""
import json
from pathlib import Path
import unittest
import test_mobile_registry as sql_tests
import test_mobile_release as base
import mobile_release as r
from test_supabase_storage import server

@unittest.skipUnless(sql_tests.DSN, 'isolated PostgreSQL DSN not explicitly provided')
class PrivateRegistrySQLTests(sql_tests.RegistrySQLTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Exercise the exact candidate advertisement function, not its unrelated
        # production Auth/PI grants/RPC. Rewrite only schema identity for isolation.
        candidate = (Path(__file__).resolve().parents[2] /
                     'supabase/candidates/mobile_private_delivery.sql').read_text()
        function = candidate.split('CREATE OR REPLACE FUNCTION mobile_release.advertise', 1)[1]
        function = 'CREATE OR REPLACE FUNCTION mobile_release.advertise' + function.split(
            'ALTER FUNCTION mobile_release.advertise(jsonb) OWNER TO mobile_release_owner;', 1)[0]
        cls.conn.execute(function)
        cls.conn.execute('ALTER FUNCTION mobile_release.advertise(jsonb) OWNER TO mobile_release_owner')

    def payload(self, code=6, commit='b'*40):
        payload = super().payload(code, commit)
        del payload['apk_url']
        return dict(payload, provider='supabase-rest', bucket=r.PRIVATE_BUCKET)

    def test_python_publisher_against_real_scoped_sql_adapter(self):
        # Run the real adapter while admitting the existing publisher role on
        # every physical connection. No login/role provisioning in shared cluster.
        from unittest.mock import patch
        connect = self.pg.connect
        def scoped_connect(*args, **kwargs):
            conn = connect(*args, **kwargs)
            conn.execute('set role mobile_release_publisher')
            return conn
        registry = r.PostgresRegistry(sql_tests.DSN, contract=r.PRIVATE_CONTRACT, schema=self.schema)
        spec = r.Spec('1.0.5', 6, 'b'*40, base.SIGNER)
        events = []
        with server() as (endpoint, state):
            storage = r.SupabaseStorage(endpoint, r.PRIVATE_BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            args = (spec, base.APK, r.private_metadata(spec, base.APK), base.Github(events),
                    storage, registry, lambda *a: None, None)
            with patch.object(self.pg, 'connect', side_effect=scoped_connect):
                payload = r.publish(*args)
                self.assertEqual(r.publish(*args), payload)
            self.assertEqual(payload, self.call('select mobile_release.latest()', role='mobile_release_reader'))
            self.assertEqual(list(state['objects'].values()), [base.APK])
            self.assertNotIn('activate', events)

    def test_private_contract_rejects_persistent_urls_wrong_locator_extra_and_size(self):
        self.reserve()
        for changes in ({'apk_url':'https://public.example/app.apk'}, {'signedURL':'secret'},
                        {'provider':'s3'}, {'bucket':'other'}, {'size':536870913},
                        {'object_key':'other'}, {'version_code':True}, {'size':True}):
            with self.subTest(changes=changes), self.assertRaises(self.pg.Error):
                self.advertise(dict(self.payload(), **changes))
        self.assertIsNone(self.call('select mobile_release.latest()', role='mobile_release_reader'))
