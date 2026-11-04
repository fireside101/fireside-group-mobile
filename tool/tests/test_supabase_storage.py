"""Native REST contracts over disposable loopback HTTP; never production calls."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import sys
import threading
from typing import Any
from unittest.mock import patch
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_release as r
import test_mobile_release as base


@contextmanager
def server():
    state: dict[str, Any] = dict(objects={}, requests=[], mode='normal', authorized=True)

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def log_message(self, format, *args): pass
        def range_reply(self, body):
            start, end = map(int, self.headers['Range'].removeprefix('bytes=').split('-'))
            end = min(end, len(body) - 1)
            part = body[start:end+1]
            if state['mode'] == 'corrupt-range' and start:
                part = bytes([part[0] ^ 1]) + part[1:]
            self.send_response(206)
            self.send_header('Content-Length', str(len(part)))
            offset = 1 if state['mode'] == 'wrong-range' else 0
            total = len(body) + (1 if state['mode'] == 'changed-total' and start else 0)
            self.send_header('Content-Range', f'bytes {start+offset}-{end}/{total}')
            etag = 'changed' if state['mode'] == 'changed-etag' and start else 'original'
            if state['mode'] != 'missing-etag':
                prefix = 'W/' if state['mode'] == 'weak-etag' else ''
                self.send_header('ETag', prefix + '"' + etag + '"')
            self.end_headers()
            if state['mode'] == 'truncated-range':
                self.wfile.write(part[:10])
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
            else:
                self.wfile.write(part)
        def reply(self, status, body):
            self.send_response(status)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # client correctly aborts a response exceeding its range cap
        def auth(self):
            state.setdefault('protocols', []).append(self.request_version)
            state['requests'].append((self.command, self.path, dict(self.headers)))
            if (not state['authorized'] or self.headers.get('Authorization') != 'Bearer SYNTHETIC'
                    or self.headers.get('apikey') != 'SYNTHETIC'):
                self.reply(403, b'{"statusCode":"403","message":"sensitive upstream diagnostic"}')
                return False
            return True
        def do_POST(self):
            data = self.rfile.read(int(self.headers['Content-Length']))
            if not self.auth(): return
            if state['mode'] == 'redirect':
                self.send_response(307)
                self.send_header('Location', '/credential-leak')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if state['mode'] == 'bad-envelope':
                self.reply(400, b'{"statusCode":"403","error":"Duplicate"}')
                return
            if self.path in state['objects']:
                self.reply(state.get('duplicate_status', 400), b'{"statusCode":"409","error":"Duplicate","message":"already exists"}')
                return
            if self.headers.get('x-upsert') != 'false':
                self.reply(500, b'unsafe upload')
                return
            if state['mode'] != 'drop-before':
                state['objects'][self.path] = data
            if state['mode'].startswith('drop-'):
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            self.reply(200, b'{"Key":"test/fixture.apk"}')
        def do_GET(self):
            if not self.auth(): return
            if state['mode'] == 'get-redirect':
                self.send_response(302)
                self.send_header('Location', '/credential-leak')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if state['mode'] == 'read-drop':
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            if self.path not in state['objects']:
                self.reply(404, b'not found')
                return
            body = state['objects'][self.path]
            if state['mode'] != 'ignore-range' and self.headers.get('Range') and len(body) > 4194304:
                self.range_reply(body)
                return
            self.reply(200, body)

    http = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=lambda: http.serve_forever(poll_interval=0.01))
    thread.start()
    try:
        yield f'http://127.0.0.1:{http.server_port}/storage/v1', state
    finally:
        http.shutdown()
        thread.join()
        http.server_close()


class SupabaseStorageTests(unittest.TestCase):
    def test_ranged_read_exact_size_hash_and_credentials_stdin_only(self):
        import hashlib
        import os
        import tempfile
        data = b'full-apk-range-proof' * 500000
        with server() as (endpoint, state), tempfile.TemporaryDirectory() as home:
            state['objects']['/storage/v1/object/test-mobile/full.apk'] = data
            Path(home, '.curlrc').write_text('proxy = "http://127.0.0.1:1"\nlocation\n')
            original_run = r.subprocess.run
            calls = []
            def checked_run(args, **kwargs):
                calls.append(args)
                self.assertNotIn('SYNTHETIC', ' '.join(args))
                self.assertEqual(args[:2], ['curl', '-q'])
                self.assertIn('--http1.1', args)
                self.assertIn('--noproxy', args)
                self.assertNotIn('--insecure', args)
                return original_run(args, **kwargs)
            with patch.dict(os.environ, HOME=home, HTTPS_PROXY='http://127.0.0.1:1', HTTP_PROXY='http://127.0.0.1:1'), patch.object(r.subprocess, 'run', side_effect=checked_run):
                actual = self.storage(endpoint).read('full.apk')
            self.assertEqual(len(actual), len(data))
            self.assertEqual(hashlib.sha256(actual).hexdigest(), hashlib.sha256(data).hexdigest())
            self.assertEqual(len(calls), 3)
            requests = state['requests']
            self.assertEqual([h.get('Range') for _, _, h in requests],
                             ['bytes=0-4194303', 'bytes=4194304-8388607', 'bytes=8388608-9999999'])
            self.assertEqual(requests[1][2]['If-Match'], '"original"')
            self.assertEqual(state['protocols'], ['HTTP/1.1'] * 3)

    def test_curl_large_post_redirect_and_uncertain_responses_never_replay(self):
        for mode in ('redirect', 'drop-before', 'drop-after'):
            with self.subTest(mode=mode), server() as (endpoint, state):
                state['mode'] = mode
                with self.assertRaises(r.Held):
                    self.storage(endpoint).put_if_absent('full.apk', b'x' * 1100000)
                self.assertEqual([m for m, _, _ in state['requests']], ['POST'])
                self.assertEqual(bool(state['objects']), mode == 'drop-after')

    def test_curl_get_redirect_never_forwards_credentials(self):
        with server() as (endpoint, state):
            state['mode'] = 'get-redirect'
            with self.assertRaises(r.Held):
                self.storage(endpoint).read('fixture.apk')
            self.assertEqual(len(state['requests']), 1)
            self.assertNotIn('credential-leak', state['requests'][0][1])

    def test_range_protocol_errors_fail_closed_without_writes(self):
        for mode in ('ignore-range', 'wrong-range', 'changed-etag', 'truncated-range',
                     'changed-total', 'missing-etag', 'weak-etag'):
            with self.subTest(mode=mode), server() as (endpoint, state):
                state['mode'] = mode
                state['objects']['/storage/v1/object/test-mobile/full.apk'] = b'x' * 5000000
                with self.assertRaises(r.Held):
                    self.storage(endpoint).read('full.apk')
                self.assertTrue(all(m == 'GET' for m, _, _ in state['requests']))
                self.assertLessEqual(len(state['requests']), 2)

    def test_ranged_same_length_corruption_is_held_by_exact_caller_readback(self):
        with server() as (endpoint, state):
            state['mode'] = 'corrupt-range'
            original = b'x' * 5000000
            with self.assertRaisesRegex(r.Held, 'byte readback mismatch'):
                self.storage(endpoint).put_if_absent('full.apk', original)
            self.assertEqual(list(state['objects'].values()), [original])
            self.assertEqual([m for m, _, _ in state['requests']], ['POST', 'GET', 'GET'])

    def test_large_post_uses_bounded_curl_transport_not_single_ssl_write(self):
        with server() as (endpoint, state):
            storage = self.storage(endpoint)
            data = b'large-APK-transport' * 100000
            with patch.object(storage._opener, 'open', side_effect=AssertionError('single SSL write must not run')):
                status, _ = storage._request('POST', 'large.apk', data)
            self.assertEqual(status, 200)
            self.assertEqual(state['objects']['/storage/v1/object/test-mobile/large.apk'], data)

    def storage(self, endpoint):
        return r.SupabaseStorage(endpoint, 'test-mobile', 'SYNTHETIC', allow_loopback_http=True)

    def test_create_duplicate_preserves_original_and_readback(self):
        with server() as (endpoint, state):
            storage = self.storage(endpoint)
            storage.put_if_absent('nested/fixture.apk', b'original')
            storage.put_if_absent('nested/fixture.apk', b'original')
            self.assertEqual(storage.read('nested/fixture.apk'), b'original')
            with self.assertRaisesRegex(r.Held, 'byte readback mismatch'):
                storage.put_if_absent('nested/fixture.apk', b'replacement')
            self.assertEqual(storage.read('nested/fixture.apk'), b'original')
            posts = [{k.lower(): v for k, v in headers.items()}
                     for method, _, headers in state['requests'] if method == 'POST']
            self.assertEqual(len(posts), 3)
            self.assertTrue(all(h['x-upsert'] == 'false' for h in posts))
            self.assertTrue(all(h['content-type'] == 'application/vnd.android.package-archive' for h in posts))

    def test_duplicate_http_409_and_authenticated_read_denial(self):
        with server() as (endpoint, state):
            storage = self.storage(endpoint)
            storage.put_if_absent('fixture.apk', b'original')
            state['duplicate_status'] = 409
            storage.put_if_absent('fixture.apk', b'original')
            state['authorized'] = False
            with self.assertRaisesRegex(r.Held, 'authenticated read held'):
                storage.read('fixture.apk')
            self.assertEqual(list(state['objects'].values()), [b'original'])

    def test_supabase_s3_is_not_a_configuration_escape_hatch(self):
        with self.assertRaisesRegex(r.Held, 'conditional create unsupported'):
            r.storage_from_environment(dict(MOBILE_STORAGE_APPROVED='true',
                MOBILE_STORAGE_PROVIDER='s3',
                MOBILE_S3_ENDPOINT='https://custom.example/storage/v1/s3'))

    def test_auth_and_nonduplicate_errors_are_held_no_read_or_retry(self):
        for mode in ('auth', 'bad-envelope', 'redirect'):
            with self.subTest(mode=mode), server() as (endpoint, state):
                state['authorized'] = mode != 'auth'
                state['mode'] = mode
                with self.assertRaises(r.Held) as caught:
                    self.storage(endpoint).put_if_absent('fixture.apk', b'original')
                self.assertNotIn('sensitive', str(caught.exception))
                self.assertNotIn('SYNTHETIC', str(caught.exception))
                self.assertEqual(len(state['requests']), 1)
                self.assertEqual(state['objects'], {})

    def test_uncertain_write_does_not_retry_or_claim_success(self):
        for mode in ('drop-before', 'drop-after'):
            with self.subTest(mode=mode), server() as (endpoint, state):
                state['mode'] = mode
                storage = self.storage(endpoint)
                with self.assertRaisesRegex(r.Held, 'uncertain'):
                    storage.put_if_absent('fixture.apk', b'original')
                self.assertEqual(len(state['requests']), 1)
                self.assertEqual(bool(state['objects']), mode == 'drop-after')
                # Only an explicit retry can resolve the outcome, with create-only + exact GET.
                state['mode'] = 'normal'
                storage.put_if_absent('fixture.apk', b'original')
                self.assertEqual(storage.read('fixture.apk'), b'original')

    def test_failed_readback_is_held_and_never_reposts(self):
        with server() as (endpoint, state):
            state['mode'] = 'read-drop'
            with self.assertRaises(r.Held):
                self.storage(endpoint).put_if_absent('fixture.apk', b'original')
            self.assertEqual([m for m, _, _ in state['requests']], ['POST', 'GET'])
            self.assertEqual(list(state['objects'].values()), [b'original'])

    def test_unsupported_private_contract_refused_before_lock(self):
        with server() as (endpoint, state):
            storage = self.storage(endpoint)
            self.assertEqual(storage.reference('nested/fixture.apk'), dict(
                provider='supabase-rest', bucket='test-mobile', object_key='nested/fixture.apk'))
            registry = base.Registry()
            registry.contract = 'unsupported-private-contract'
            with self.assertRaisesRegex(r.Held, 'unsupported registry contract'):
                r.publish(r.Spec('1.0.5', 6, 'b'*40, base.SIGNER), base.APK, {},
                          base.Github(registry.events), storage, registry,
                          lambda *args: None, 'https://fake-public.example')
            self.assertEqual(registry.events, [])
            with patch.object(r.PostgresRegistry, 'publication_lock') as lock:
                with self.assertRaisesRegex(r.Held, 'unsupported registry contract'):
                    r.publish(r.Spec('1.0.5', 6, 'b'*40, base.SIGNER), base.APK, {},
                              base.Github(registry.events), storage,
                              r.PostgresRegistry('unused-synthetic-dsn', contract='unsupported-private-contract'),
                              lambda *args: None, None)
                lock.assert_not_called()
            self.assertEqual(state['requests'], [])

    def test_production_config_has_no_fallback_and_rejects_unsafe_targets(self):
        valid = dict(MOBILE_STORAGE_APPROVED='true', MOBILE_STORAGE_PROVIDER='supabase-rest',
                     MOBILE_SUPABASE_STORAGE_ENDPOINT='https://storage.example/storage/v1',
                     MOBILE_SUPABASE_STORAGE_BUCKET='test-mobile',
                     MOBILE_SUPABASE_STORAGE_TOKEN='SYNTHETIC')
        storage, public_base = r.storage_from_environment(valid)
        self.assertIsInstance(storage, r.SupabaseStorage)
        self.assertIsNone(public_base)
        for changes in ({'MOBILE_STORAGE_PROVIDER': ''}, {'MOBILE_STORAGE_PROVIDER': 'typo'},
                        {'MOBILE_STORAGE_APPROVED': 'false'}, {'MOBILE_SUPABASE_STORAGE_TOKEN': ''},
                        {'MOBILE_SUPABASE_STORAGE_ENDPOINT': 'http://127.0.0.1:9000/storage/v1'},
                        {'MOBILE_SUPABASE_STORAGE_BUCKET': '../other'}):
            with self.subTest(changes=changes), self.assertRaises(r.Held):
                r.storage_from_environment(dict(valid, **changes))
        with server() as (endpoint, state):
            storage = self.storage(endpoint)
            for key in ('../other', '/absolute', 'a//b', 'a?secret', 'a/./b', 'a%2fb'):
                with self.subTest(key=key), self.assertRaises(r.Held):
                    storage.put_if_absent(key, b'original')
            self.assertEqual(state['requests'], [])


if __name__ == '__main__': unittest.main()
