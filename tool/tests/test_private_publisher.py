"""Private contract publisher: loopback transport, no live cloud services."""
import unittest
from unittest.mock import patch
import test_mobile_release as base
import mobile_release as r
from test_supabase_storage import server

CONTRACT = 'mobile_release_private_v1'
BUCKET = 'fireside-mobile-releases'

class PrivatePublisherTests(unittest.TestCase):
    def setUp(self):
        self.spec = r.Spec('1.0.5', 6, 'b'*40, base.SIGNER)
        self.registry = base.Registry()
        self.registry.contract = CONTRACT
        self.github = base.Github(self.registry.events)

    def metadata(self):
        return dict(versionName=self.spec.version, versionCode=self.spec.code,
                    apkSize=len(base.APK), apkSha256=base.SHA,
                    deliveryContract=CONTRACT)

    def publish(self, storage, metadata=None, public_base=None):
        return r.publish(self.spec, base.APK, self.metadata() if metadata is None else metadata,
                         self.github, storage, self.registry, lambda *a: None, public_base)

    def test_complete_private_success_retry_exact_locator_no_public_activation(self):
        with server() as (endpoint, state):
            storage = r.SupabaseStorage(endpoint, BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            payload = self.publish(storage)
            self.assertEqual(set(payload), {'package','version_code','version_name','tag','commit',
                'signer_sha256','sha256','size','provider','bucket','object_key'})
            self.assertEqual(payload['provider'], 'supabase-rest')
            self.assertEqual(payload['bucket'], BUCKET)
            self.assertEqual(payload['object_key'], self.spec.object_key(base.SHA))
            self.assertEqual(self.publish(storage), payload)
            self.assertEqual(list(state['objects'].values()), [base.APK])
            self.assertNotIn('activate', self.registry.events)

    def test_mixed_modes_and_unsupported_contract_refused_before_lock_or_writes(self):
        with server() as (endpoint, state):
            storage = r.SupabaseStorage(endpoint, BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            for contract in ('mobile_release_v1', 'unsupported', None):
                self.registry.contract = contract
                with self.assertRaises(r.Held): self.publish(storage)
            self.registry.contract = CONTRACT
            with self.assertRaises(r.Held): self.publish(base.Storage([]))
            with self.assertRaises(r.Held): self.publish(storage, public_base='https://public.example')
            with patch.object(r.PostgresRegistry, 'publication_lock') as lock:
                self.registry = r.PostgresRegistry('unused', contract='unsupported')
                with self.assertRaises(r.Held): self.publish(storage)
                lock.assert_not_called()
            self.assertEqual(state['requests'], [])

    def test_private_metadata_rejects_urls_extra_keys_and_numeric_aliases_before_reserve(self):
        with server() as (endpoint, state):
            storage = r.SupabaseStorage(endpoint, BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            for change in ({'apkUrl':'https://public.example/app.apk'}, {'signedURL':'secret'},
                           {'versionCode':6.0}, {'apkSize':True}, {'deliveryContract':'unknown'}):
                with self.assertRaises(r.Held): self.publish(storage, dict(self.metadata(), **change))
            self.assertEqual(self.registry.events, [])
            self.assertEqual(state['requests'], [])

    def test_readback_or_latest_failure_never_activates(self):
        for target in ('read', 'read_latest'):
            with server() as (endpoint, state):
                storage = r.SupabaseStorage(endpoint, BUCKET, 'SYNTHETIC', allow_loopback_http=True)
                registry = base.Registry(); registry.contract = CONTRACT
                self.registry = registry
                setattr(registry, target, lambda *a: None)
                with self.assertRaises(r.Held): self.publish(storage)
                self.assertNotIn('activate', self.github.events)

    def test_workflow_private_metadata_and_allocation_pair_are_explicit(self):
        from pathlib import Path
        text = (Path(__file__).resolve().parents[2] / '.github/workflows/flutter.yml').read_text()
        allocate = text.split('Allocate immutable commit version before signing', 1)[1].split('run: python tool/mobile_release.py --allocate')[0]
        for key in ('MOBILE_STORAGE_PROVIDER', 'MOBILE_SUPABASE_STORAGE_BUCKET', 'MOBILE_S3_PUBLIC_BASE'):
            self.assertIn(key, allocate)
        self.assertIn('private_metadata', text)
        self.assertIn('private bootstrap remains held', text)

    def test_workflow_private_bootstrap_script_executes_without_url(self):
        import os
        from pathlib import Path
        import subprocess
        import tempfile
        import textwrap
        root = Path(__file__).resolve().parents[2]
        text = (root / '.github/workflows/flutter.yml').read_text()
        step = text.split('      - name: Build APK and contract-specific bootstrap metadata', 1)[1].split('      - name:', 1)[0]
        script = textwrap.dedent(step.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'tool').symlink_to(root / 'tool', target_is_directory=True)
            (path / 'pubspec.yaml').write_text('version: 1.0.5+6\n')
            (path / 'build/app/outputs/flutter-apk').mkdir(parents=True)
            (path / 'build/app/outputs/flutter-apk/app-release.apk').write_bytes(base.APK)
            (path / 'flutter').write_text('#!/bin/sh\nprintf "%s\\n" "$@" > flutter-args\n')
            (path / 'flutter').chmod(0o700)
            env = dict(os.environ, PATH=tmp+os.pathsep+os.environ['PATH'],
                       MOBILE_REGISTRY_CONTRACT=CONTRACT, MOBILE_BUILD_NAME=self.spec.version,
                       SUPABASE_URL='https://synthetic.invalid', SUPABASE_ANON_KEY='SYNTHETIC',
                       PORTAL_API_BASE_URL='https://synthetic.invalid',
                       MOBILE_BUILD_CODE=str(self.spec.code), GITHUB_SHA=self.spec.commit,
                       MOBILE_PRODUCTION_SIGNER_SHA256=base.SIGNER)
            result = subprocess.run(['bash','-eu','-c',script], cwd=tmp, env=env,
                                    text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            flutter_args = (path/'flutter-args').read_text().splitlines()
            self.assertIn('--dart-define=UPDATE_REGISTRY=private', flutter_args)
            self.assertIn('--dart-define=UPDATE_STORAGE_BASE=https://supabase.firesideafrica.cloud/storage/v1/object/sign', flutter_args)
            import json
            self.assertEqual(json.loads((path/'release/update.json').read_text()), self.metadata())

    def test_environment_pair_validation_precedes_allocation(self):
        valid = dict(MOBILE_REGISTRY_CONTRACT=CONTRACT, MOBILE_STORAGE_PROVIDER='supabase-rest',
                     MOBILE_SUPABASE_STORAGE_BUCKET=BUCKET)
        r.check_contract_environment(valid)
        for changes in ({'MOBILE_REGISTRY_CONTRACT':'unknown'}, {'MOBILE_STORAGE_PROVIDER':'s3'},
                        {'MOBILE_SUPABASE_STORAGE_BUCKET':'other'}, {'MOBILE_S3_PUBLIC_BASE':'https://public.example'}):
            with self.assertRaises(r.Held): r.check_contract_environment(dict(valid, **changes))
        with self.assertRaises(r.Held):
            r.check_contract_environment(dict(valid, MOBILE_REGISTRY_CONTRACT='mobile_release_v1'))

    def test_wrong_bucket_and_collision_refused(self):
        with server() as (endpoint, state):
            wrong = r.SupabaseStorage(endpoint, 'other', 'SYNTHETIC', allow_loopback_http=True)
            with self.assertRaises(r.Held): self.publish(wrong)
            self.assertEqual(state['requests'], [])
            storage = r.SupabaseStorage(endpoint, BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            key = self.spec.object_key(base.SHA)
            state['objects'][f'/storage/v1/object/{BUCKET}/{key}'] = b'collision'
            with self.assertRaises(r.Held): self.publish(storage)
            self.assertNotIn('advertise', self.registry.events)
