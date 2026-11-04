"""Offline publisher contract: no Flutter, network, credentials or database."""
import hashlib
import sys
import unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    import mobile_release as release
except ImportError:
    release = None

APK = b'synthetic signed apk bytes; verifier adapter only'
SHA = hashlib.sha256(APK).hexdigest()
SIGNER = 'a' * 64

class Registry:
    def __init__(self):
        self.events = []
        self.payload = None
    def reserve(self, spec):
        self.events.append('reserve')
    def advertise(self, payload):
        self.events.append('advertise')
        self.payload = payload
    def read_latest(self): return self.payload
    def read(self, commit):
        return self.payload

class Github:
    def __init__(self, events): self.events = events
    def activate(self, spec): self.events.append('activate')
    def ensure(self, spec, apk, metadata): self.events.append('github')
    def download(self, spec):
        self.events.append('download')
        return APK

class Storage:
    def __init__(self, events): self.events = events; self.objects = {}
    def put_if_absent(self, key, data):
        self.events.append('s3')
        self.objects.setdefault(key, data)
    def read(self, key): return self.objects[key]

class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(release, 'release foundation is not implemented')
        self.spec = release.Spec('1.0.5', 6, 'b'*40, SIGNER)
        self.registry = Registry()
        self.github = Github(self.registry.events)
        self.storage = Storage(self.registry.events)
    def publish(self, **kw):
        return release.publish(self.spec, APK, {}, self.github, self.storage,
            self.registry, kw.get('verify', lambda data, spec: None),
            'https://approved.example/mobile')
    def test_success_order_exact_bytes_and_readback(self):
        payload = self.publish()
        self.assertEqual(self.registry.events, ['reserve', 'github', 'download', 's3', 'advertise', 'activate'])
        self.assertEqual(payload['sha256'], SHA)
        self.assertEqual(self.storage.read(payload['object_key']), APK)
        self.assertEqual(self.registry.payload, payload)
    def test_idempotent_rerun_same_payload_and_object(self):
        first = self.publish()
        self.assertEqual(first, self.publish())
        self.assertEqual(len(self.storage.objects), 1)
    def test_github_wrong_bytes_never_uploads_or_advertises(self):
        self.github.download = lambda spec: b'wrong'
        with self.assertRaises(release.Held): self.publish()
        self.assertNotIn('s3', self.registry.events)
        self.assertNotIn('advertise', self.registry.events)
    def test_s3_failure_never_advertises(self):
        def fail(*args): raise release.Held('upload held')
        self.storage.put_if_absent = fail
        with self.assertRaises(release.Held): self.publish()
        self.assertNotIn('advertise', self.registry.events)
    def test_existing_s3_collision_never_overwrites_or_advertises(self):
        key = self.spec.object_key(SHA)
        self.storage.objects[key] = b'collision'
        with self.assertRaises(release.Held): self.publish()
        self.assertEqual(self.storage.objects[key], b'collision')
        self.assertNotIn('advertise', self.registry.events)
    def test_registry_failure_retry_keeps_verified_object(self):
        original = self.registry.advertise
        self.registry.advertise = lambda payload: (_ for _ in ()).throw(release.Held('registry held'))
        with self.assertRaises(release.Held): self.publish()
        self.registry.advertise = original
        self.publish()
        self.assertEqual(len(self.storage.objects), 1)
    def test_signer_or_package_failure_precedes_all_side_effects(self):
        def deny(*args): raise release.Held('identity mismatch')
        with self.assertRaises(release.Held): self.publish(verify=deny)
        self.assertEqual(self.registry.events, [])
    def test_unconfigured_registry_fails_closed(self):
        with self.assertRaises(release.Held): release.PostgresRegistry.from_environment({})
    def test_invalid_identity_inputs(self):
        for code in [True, 0, -1, 2100000001]:
            with self.assertRaises(release.Held): release.Spec('1.0.5', code, 'b'*40, SIGNER)
        for signer in ['', 'unverified', 'a'*63]:
            with self.assertRaises(release.Held): release.Spec('1.0.5', 6, 'b'*40, signer)
    def test_url_credentials_query_and_http_are_rejected_before_effects(self):
        for url in ['http://example.com', 'https://user:secret@example.com', 'https://example.com?k=secret']:
            with self.assertRaises(release.Held):
                release.publish(self.spec, APK, {}, self.github, self.storage, self.registry,
                    lambda *args: None, url)
        self.assertEqual(self.registry.events, [])
    def test_registry_readback_mismatch_is_not_success(self):
        self.registry.read = lambda commit: None
        with self.assertRaises(release.Held): self.publish()

if __name__ == '__main__': unittest.main()
