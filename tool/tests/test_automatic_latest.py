"""Owner-approved stable mobile releases; private updater metadata stays private-only."""
import json
import unittest
from unittest.mock import patch
import test_mobile_release as base
import mobile_release as r
from test_github_draft_lookup import GithubAPI
from test_supabase_storage import server


class AutomaticLatestTests(unittest.TestCase):
    def setUp(self):
        self.spec = r.Spec('1.0.11', 11, 'c'*40, base.SIGNER)

    def test_normal_private_release_activates_after_all_byte_and_registry_proofs(self):
        registry = base.Registry(); registry.contract = r.PRIVATE_CONTRACT
        gh = base.Github(registry.events)
        with server() as (endpoint, state):
            storage = r.SupabaseStorage(endpoint, r.PRIVATE_BUCKET, 'SYNTHETIC', allow_loopback_http=True)
            receipt = r.publish(self.spec, base.APK, r.private_metadata(self.spec, base.APK),
                                gh, storage, registry, lambda *a: None, None)
        self.assertEqual(registry.events, ['reserve', 'github', 'download', 'advertise', 'activate'])
        self.assertEqual(receipt, registry.read_latest())
        self.assertNotIn('apk_url', receipt)
        self.assertNotIn('apkUrl', r.private_metadata(self.spec, base.APK))

    def test_stable_activation_sets_every_visibility_field_and_reads_exact_id_and_latest(self):
        api = GithubAPI(self.spec)
        with patch.object(r.subprocess, 'run', side_effect=api):
            r.GithubRelease(public_release_approved=True).activate(self.spec)
        edit = api.writes()[0]
        for flag in ('--draft=false', '--prerelease=false', '--latest=true'):
            self.assertIn(flag, edit)
        reads = [a[-1] for a in api.calls if a[:2] == ['gh', 'api']]
        self.assertIn(f'repos/{r.REPOSITORY}/releases/434159539', reads)
        self.assertIn(f'repos/{r.REPOSITORY}/releases/latest', reads)

    def test_public_disclosure_without_approval_is_refused_before_mutation(self):
        gh = r.GithubRelease()
        with patch.object(r, 'run', return_value=json.dumps({'private': False})) as commands:
            with self.assertRaises(r.Held): gh.activate(self.spec)
        self.assertEqual(commands.call_count, 1)

    def test_stable_private_retry_requires_exact_registry_receipt(self):
        for receipt, prerelease, allowed in ((True, False, True), (False, False, False), (True, True, False)):
            gh = r.GithubRelease(public_release_approved=True)
            gh.private_mode = True; gh.allow_published = receipt
            api = GithubAPI(self.spec); api.apk = base.APK
            api.info.update(draft=False, prerelease=prerelease)
            with patch.object(r.subprocess, 'run', side_effect=api):
                if allowed: gh.ensure(self.spec, base.APK, {})
                else:
                    with self.assertRaises(r.Held): gh.ensure(self.spec, base.APK, {})

    def test_false_latest_or_exact_identity_readback_is_not_success(self):
        for bad in ('latest', 'exact'):
            api = GithubAPI(self.spec)
            def command(args, **kwargs):
                result = api(args, **kwargs)
                if api.writes() and args[-1].endswith('/releases/' + ('latest' if bad == 'latest' else '434159539')):
                    result.stdout = json.dumps(dict(api.info, prerelease=True))
                return result
            with patch.object(r.subprocess, 'run', side_effect=command):
                with self.assertRaises(r.Held):
                    r.GithubRelease(public_release_approved=True).activate(self.spec)
