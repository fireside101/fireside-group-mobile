"""Bootstrap must be an explicit private, non-latest handoff, not legacy discovery."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import test_mobile_release as base
import mobile_release as r
from test_supabase_storage import server


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.spec = r.Spec('1.0.5', 6, 'b'*40, base.SIGNER)

    def test_private_activation_uses_prerelease_and_exact_readback(self):
        gh = r.GithubRelease()
        draft = dict(draft=True, target_commitish=self.spec.commit)
        final = dict(tag_name=self.spec.tag, draft=False, prerelease=True)
        with patch.object(gh, 'tag_commit', side_effect=[None, self.spec.commit]), patch.object(
                r, 'run', side_effect=[json.dumps({'private': True}), json.dumps(draft), '', json.dumps(final)]) as commands:
            gh.activate_bootstrap(self.spec)
        edit = commands.call_args_list[2].args[0]
        self.assertIn('--prerelease=true', edit)
        self.assertIn('--latest=false', edit)
        self.assertNotIn('--latest=true', edit)
        self.assertTrue(commands.call_args_list[3].args[0][-1].endswith('/tags/'+self.spec.tag))

    def test_public_repo_refused_before_edit(self):
        with patch.object(r, 'run', return_value=json.dumps({'private': False})) as commands:
            with self.assertRaises(r.Held): r.GithubRelease().activate_bootstrap(self.spec)
            self.assertEqual(commands.call_count, 1)

    def test_explicit_public_disclosure_and_failed_readbacks(self):
        draft = dict(draft=True, target_commitish=self.spec.commit)
        final = dict(tag_name=self.spec.tag, draft=False, prerelease=True)
        for result, accepted in ((final, True), (dict(final, prerelease=False), False),
                                 (dict(final, draft=True), False), (dict(final, tag_name='wrong'), False)):
            gh = r.GithubRelease(public_bootstrap_approved=True)
            with patch.object(gh, 'tag_commit', side_effect=[None, self.spec.commit]), patch.object(
                    r, 'run', side_effect=[json.dumps({'private': False}), json.dumps(draft), '', json.dumps(result)]):
                if accepted:
                    gh.activate_bootstrap(self.spec)
                else:
                    with self.assertRaises(r.Held): gh.activate_bootstrap(self.spec)

    def test_published_private_retry_requires_receipt_and_prerelease(self):
        import subprocess
        gh = r.GithubRelease(); gh.private_mode = True
        info = dict(draft=False, prerelease=True)
        for receipt, prerelease, allowed in ((True, True, True), (False, True, False), (True, False, False)):
            gh.allow_published = receipt
            with patch.object(gh, 'tag_commit', return_value=self.spec.commit), patch.object(
                    r.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '{}', '')), patch.object(
                    r, 'run', return_value=json.dumps(dict(info, prerelease=prerelease))), patch.object(
                    gh, '_download', side_effect=[base.APK, b'{}']):
                if allowed:
                    gh.ensure(self.spec, base.APK, {})
                else:
                    with self.assertRaises(r.Held): gh.ensure(self.spec, base.APK, {})

    def test_workflow_native_verifier_executes_using_both_metadata_contracts(self):
        import os
        import subprocess
        import tempfile
        import textwrap
        root = Path(__file__).resolve().parents[2]
        text = (root/'.github/workflows/flutter.yml').read_text()
        step = text.split('      - name: Verify pinned production package and signer before artifact retention', 1)[1].split('      - uses:', 1)[0]
        script = textwrap.dedent(step.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path/'tool').symlink_to(root/'tool', target_is_directory=True)
            (path/'release').mkdir()
            (path/'release'/self.spec.apk_name).write_bytes(base.APK)
            tools = path/'build-tools/1'; tools.mkdir(parents=True)
            for name, output in (('apksigner', 'Signer #1 certificate SHA-256 digest: '+base.SIGNER),
                                 ('aapt', f"package: name='{r.PACKAGE}' versionCode='{self.spec.code}' versionName='{self.spec.version}'")):
                tool = tools/name
                tool.write_text('#!/bin/sh\nprintf "%s\\n" '+__import__('shlex').quote(output)+'\n')
                tool.chmod(0o700)
            env = dict(os.environ, ANDROID_HOME=tmp, GITHUB_SHA=self.spec.commit,
                       MOBILE_PRODUCTION_SIGNER_SHA256=base.SIGNER)
            for metadata in (r.private_metadata(self.spec, base.APK), dict(r.private_metadata(self.spec, base.APK), apkUrl='https://synthetic.invalid/app.apk')):
                (path/'release/update.json').write_text(json.dumps(metadata))
                result = subprocess.run(['bash', '-eu', '-c', script], cwd=tmp, env=env,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_private_promotion_bootstrap_after_exact_receipts_and_retry(self):
        registry = base.Registry(); registry.contract = r.PRIVATE_CONTRACT
        gh = base.Github(registry.events)
        gh.activate_bootstrap = lambda spec: registry.events.append('bootstrap')
        with server() as (endpoint, state):
            storage = r.SupabaseStorage(endpoint, r.PRIVATE_BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            args = (self.spec, base.APK, r.private_metadata(self.spec, base.APK), gh,
                    storage, registry, lambda *a: None, None)
            receipt = r.publish(*args, bootstrap=True)
            self.assertEqual(r.publish(*args, bootstrap=True), receipt)
            self.assertEqual(registry.events[-1], 'bootstrap')
            self.assertNotIn('activate', registry.events)
            registry.read_latest = lambda: None
            before = registry.events.count('bootstrap')
            with self.assertRaises(r.Held): r.publish(*args, bootstrap=True)
            self.assertEqual(registry.events.count('bootstrap'), before)

    def test_bootstrap_approval_requires_manual_private_release(self):
        valid = dict(GITHUB_EVENT_NAME='workflow_dispatch', MOBILE_PUBLISH_ANDROID='true',
                     MOBILE_PUBLISH_BOOTSTRAP='true', MOBILE_REGISTRY_CONTRACT=r.PRIVATE_CONTRACT)
        self.assertTrue(r.bootstrap_requested(valid))
        self.assertFalse(r.bootstrap_requested({}))
        for changes in ({'GITHUB_EVENT_NAME':'push'}, {'MOBILE_PUBLISH_ANDROID':'false'},
                        {'MOBILE_REGISTRY_CONTRACT':r.PUBLIC_CONTRACT}, {'MOBILE_PUBLISH_BOOTSTRAP':'yes'}):
            with self.assertRaises(r.Held): r.bootstrap_requested(dict(valid, **changes))

    def test_workflow_enables_private_runtime_and_uses_camelcase_metadata(self):
        text = (Path(__file__).resolve().parents[2]/'.github/workflows/flutter.yml').read_text()
        step = text.split('      - name: Build APK and contract-specific bootstrap metadata', 1)[1].split('      - name:', 1)[0]
        self.assertIn('--dart-define=UPDATE_REGISTRY="$update_registry"', step)
        self.assertIn('--dart-define=UPDATE_STORAGE_BASE="$update_storage_base"', step)
        self.assertIn('https://supabase.firesideafrica.cloud/storage/v1/object/sign', step)
        verify = text.split('      - name: Verify pinned production package and signer before artifact retention', 1)[1].split('      - uses:', 1)[0]
        self.assertIn("m['versionName'],m['versionCode']", verify)
        self.assertNotIn("m['version_name']", verify)
