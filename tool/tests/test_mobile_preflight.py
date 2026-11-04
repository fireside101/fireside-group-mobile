"""Dedicated isolated preflight checks; no production credentials or writes."""
import contextlib
import io
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_preflight as pf
import mobile_release as release


class Fixture(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, format, *args): pass
    def do_GET(self):
        self.server.requests.append((self.command, self.path, dict(self.headers)))
        if getattr(self.server, 'redirect', False):
            self.send_response(302); self.send_header('Location', '/unapproved-target')
            self.send_header('Content-Length', '0'); self.end_headers(); return
        if self.path in ('/storage/v1/status', '/functions/v1/mobile-update/_deployment'):
            body = (b'' if self.path.endswith('/status') else json.dumps(self.server.deployment).encode())
            self.send_response(200); self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body); return
        if not self.headers.get('Authorization'):
            self.send_response(self.server.anonymous); self.send_header('Content-Length', '0'); self.end_headers(); return
        data = self.server.data
        start, end = map(int, self.headers['Range'][6:].split('-'))
        end = min(end, len(data)-1)
        body = data[start:end+1]
        self.send_response(206)
        self.send_header('Content-Range', f'bytes {start}-{end}/{self.server.total}')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('ETag', self.server.etag)
        self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        self.server.requests.append((self.command, self.path, dict(self.headers)))
        self.server.posted = self.rfile.read(int(self.headers['Content-Length']))
        if self.path == '/functions/v1/mobile-update':
            self.send_response(401); self.send_header('Content-Length', '0'); self.end_headers(); return
        if self.server.mutate: self.server.data = b'X' * len(self.server.data)
        body = json.dumps(self.server.envelope).encode()
        self.send_response(self.server.duplicate)
        self.send_header('Content-Length', str(len(body))); self.end_headers()
        self.wfile.write(body)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        self.server.data = b'synthetic APK snapshot'
        self.server.total = len(self.server.data)
        self.server.etag = '"snapshot"'
        self.server.duplicate = 409
        self.server.envelope = {'statusCode': '409', 'error': 'Duplicate'}
        self.server.anonymous = 404
        self.server.mutate = False
        self.server.requests = []
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': .01})
        self.thread.start()
        self.adapter = pf.ProbeStorage(f'http://127.0.0.1:{self.server.server_port}/storage/v1',
            release.PRIVATE_BUCKET, 'fixture-token', allow_loopback_http=True)
        self.constants = patch.multiple(pf, APK_SIZE=len(self.server.data),
            APK_SHA=__import__('hashlib').sha256(self.server.data).hexdigest())
        self.constants.start()
    def tearDown(self):
        self.constants.stop(); self.server.shutdown(); self.thread.join(); self.server.server_close()
    def test_redirect_is_not_followed_and_never_posts(self):
        self.server.redirect = True
        with self.assertRaises(release.Held): pf.probe_storage(self.adapter)
        self.assertEqual(len(self.server.requests), 1)
        self.assertNotIn('/unapproved-target', self.server.requests[0][1])
    def test_fixed_health_routes_source_and_no_credentials(self):
        self.server.deployment = dict(revision=pf.EDGE_SOURCE, handler_sha256=pf.EDGE_HANDLER)
        with patch.object(pf, 'ORIGIN', f'http://127.0.0.1:{self.server.server_port}'):
            self.assertTrue(pf.probe_health(self.adapter)['expected_source'])
            self.server.deployment['revision'] = 'wrong'
            with self.assertRaises(release.Held): pf.probe_health(self.adapter)
        self.assertTrue(all('Authorization' not in r[2] and 'Apikey' not in r[2]
                            for r in self.server.requests))
    def test_real_adapter_exact_target_duplicate_and_unchanged_readback(self):
        result = pf.probe_storage(self.adapter)
        self.assertTrue(result['exact_bytes_unchanged'])
        self.assertEqual([r[0] for r in self.server.requests], ['GET', 'GET', 'POST', 'GET'])
        self.assertEqual(len({r[1] for r in self.server.requests}), 1)
        self.assertTrue(self.server.requests[0][2]['Range'].startswith('bytes=0-'))
        self.assertEqual(self.server.posted, self.server.data)
        self.assertEqual(self.server.requests[2][2]['X-Upsert'], 'false')
        self.assertNotIn('Authorization', self.server.requests[1][2])
    def test_real_large_post_adapter_replays_only_original_bytes(self):
        import hashlib
        self.constants.stop()
        self.server.data = b'A' * (1024 * 1024 + 1)
        self.server.total = len(self.server.data)
        self.constants = patch.multiple(pf, APK_SIZE=len(self.server.data),
            APK_SHA=hashlib.sha256(self.server.data).hexdigest())
        self.constants.start()
        result = pf.probe_storage(self.adapter)
        self.assertTrue(result['exact_bytes_unchanged'])
        self.assertEqual(self.server.posted, self.server.data)
    def test_denied_403_is_accepted_without_reflecting_envelope(self):
        self.server.duplicate = 403
        self.server.envelope = {'statusCode': '403', 'error': 'secret upstream'}
        self.assertEqual(pf.probe_storage(self.adapter)['duplicate_post_status'], 403)
    def test_mutation_is_detected_even_when_post_reports_denied(self):
        self.server.mutate = True
        with self.assertRaises(release.Held): pf.probe_storage(self.adapter)
        self.assertEqual(self.server.requests[-1][0], 'GET')
    def test_successful_post_is_not_duplicate_proof_and_still_reads_back(self):
        self.server.duplicate = 200
        with self.assertRaises(release.Held): pf.probe_storage(self.adapter)
        self.assertEqual(self.server.requests[-1][0], 'GET')
    def test_wrong_total_or_weak_etag_prevents_post(self):
        for field, value in [('total', self.server.total + 1), ('etag', 'W/"snapshot"')]:
            with self.subTest(field=field):
                old = getattr(self.server, field); setattr(self.server, field, value)
                with self.assertRaises(release.Held): pf.probe_storage(self.adapter)
                setattr(self.server, field, old)
        self.assertNotIn('POST', [r[0] for r in self.server.requests])
    def test_invalid_duplicate_envelope_is_not_proof(self):
        for envelope in [{'statusCode': '403'}, ['upstream-secret'], {'statusCode': '409', 'error': 'Other'}]:
            self.server.envelope = envelope
            with self.subTest(envelope=envelope), self.assertRaises(release.Held):
                pf.probe_storage(self.adapter)
            self.assertEqual(self.server.requests[-1][0], 'GET')
    def test_native_400_duplicate_envelope_is_accepted(self):
        self.server.duplicate = 400
        self.assertEqual(pf.probe_storage(self.adapter)['duplicate_post_status'], 400)
    def test_post_transport_exception_still_reads_original(self):
        real = self.adapter._request
        def request(method, key, data=None):
            if method == 'POST': raise release.Held('secret upstream')
            return real(method, key, data)
        with patch.object(self.adapter, '_request', side_effect=request):
            with self.assertRaises(release.Held): pf.probe_storage(self.adapter)
        self.assertEqual([r[0] for r in self.server.requests], ['GET', 'GET', 'GET'])
    def test_anonymous_success_prevents_post(self):
        self.server.anonymous = 200
        with self.assertRaises(release.Held): pf.probe_storage(self.adapter)
        self.assertNotIn('POST', [r[0] for r in self.server.requests])


class AdmissionTests(unittest.TestCase):
    def env(self):
        return dict(GITHUB_ACTOR='josephndex', GITHUB_TRIGGERING_ACTOR='josephndex',
            GITHUB_REF='refs/heads/main', GITHUB_EVENT_NAME='workflow_dispatch',
            GITHUB_REPOSITORY=release.REPOSITORY)
    def test_both_actors_ref_event_and_repository_pinned(self):
        pf.admit(self.env())
        for key in self.env():
            env = self.env(); env[key] = 'untrusted'
            with self.subTest(key=key), self.assertRaises(release.Held): pf.admit(env)
    def test_token_role_expiry_metadata_not_signature_proof(self):
        import base64
        def token(role='mobile_release_storage_publisher', exp=4600):
            enc = lambda v: base64.urlsafe_b64encode(json.dumps(v).encode()).decode().rstrip('=')
            return enc({'alg': 'HS256'}) + '.' + enc({'role': role, 'iat': 1000, 'exp': exp}) + '.fixture'
        with patch.object(pf.time, 'time', return_value=1100):
            pf.check_token(token())
            for value in [token('service_role'), token(exp=1101), token(exp=9000), 'invalid']:
                with self.subTest(value=value), self.assertRaises(release.Held): pf.check_token(value)
    def test_private_configuration_checked_before_connect_or_ca_write(self):
        with patch.object(release, 'verify_environment'), patch.object(pf, 'probe_sql') as sql:
            with self.assertRaises(release.Held): pf.preflight(self.env())
            sql.assert_not_called()
    def test_runtime_rejects_before_github_metadata(self):
        with patch.object(release, 'verify_environment') as verify:
            with self.assertRaises(release.Held): pf.preflight({})
            verify.assert_not_called()
    def test_production_adapter_rejects_http(self):
        with self.assertRaises(release.Held):
            pf.ProbeStorage('http://127.0.0.1:1234/storage/v1', release.PRIVATE_BUCKET, 'x')
    def test_cli_single_fixed_json_never_exception(self):
        out = io.StringIO()
        with patch.object(pf, 'preflight', side_effect=RuntimeError('DSN secret')), contextlib.redirect_stdout(out):
            code = pf.main()
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(out.getvalue())['error'], 'preflight_held')
        self.assertNotIn('secret', out.getvalue())


class SqlTests(unittest.TestCase):
    def test_readonly_actual_adapter_contract_no_base_table_or_write_calls(self):
        from unittest.mock import MagicMock
        from types import SimpleNamespace
        good = ('mobile_release_ci_a', 'mobile_release_ci_a', True,
                False, False, False, False, False, True, False,
                True, True, True, True, True, False, False, False)
        conn = MagicMock()
        conn.execute.return_value.fetchone.side_effect = [good, (None,)]
        connection = MagicMock(); connection.__enter__.return_value = conn
        connect = MagicMock(return_value=connection)
        registry = SimpleNamespace(dsn='fixture-scoped-dsn')
        with patch.dict(sys.modules, {'psycopg': SimpleNamespace(connect=connect)}), \
                patch.object(release, 'prepare_registry_ca') as ca, \
                patch.object(release.PostgresRegistry, 'from_environment', return_value=registry):
            result = pf.probe_sql({'fixture': 'environment'})
        ca.assert_called_once_with({'fixture': 'environment'})
        self.assertIn('default_transaction_read_only=on', connect.call_args.kwargs['options'])
        self.assertTrue(result['latest_null'])
        statements = [c.args[0] for c in conn.execute.call_args_list]
        self.assertEqual(len(statements), 2)
        self.assertTrue(all(s.lstrip().upper().startswith('SELECT ') for s in statements))
        self.assertEqual(statements[-1], 'SELECT mobile_release.latest()')
        self.assertNotIn('FROM mobile_release.app', statements[0])
    def test_ca_helper_refuses_dsn_tls_downgrade_before_connect(self):
        # Real helper runs with dependency fixture only for conninfo parsing; no CA
        # material or database process is needed for the downgrade refusal.
        from types import SimpleNamespace
        import tempfile
        with tempfile.TemporaryDirectory() as runner, \
                patch.dict(sys.modules, {'psycopg.conninfo': SimpleNamespace(
                    conninfo_to_dict=lambda _: {'sslmode': 'require', 'sslrootcert': runner + '/mobile-registry-ca.pem'})}):
            with self.assertRaises(release.Held):
                release.prepare_registry_ca({'RUNNER_TEMP': runner, 'MOBILE_REGISTRY_DSN': 'fixture'})
            self.assertFalse((Path(runner) / 'mobile-registry-ca.pem').exists())


if __name__ == '__main__': unittest.main()
