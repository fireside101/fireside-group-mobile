"""GitHub's tag endpoint hides drafts: exercise the real adapter command boundary."""
import json
from pathlib import Path
import subprocess
import sys
from typing import Any
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_release as r


class GithubAPI:
    def __init__(self, spec, *, exists=True):
        self.spec = spec
        self.info = dict(id=434159539, tag_name=spec.tag, draft=True, prerelease=False,
                         target_commitish=spec.commit,
                         url=f'https://api.github.com/repos/{r.REPOSITORY}/releases/434159539')
        self.exists = exists
        self.pages: Any = [[dict(self.info, id=7, tag_name='v1.0.7')], [self.info]] if exists else [[]]
        self.calls = []
        self.errors = {}
        self.apk = b'apk'
        self.metadata = b'{}'

    def __call__(self, args, **kwargs):
        self.calls.append(args)
        assert args[:1] == ['gh'], args
        if args[:2] == ['gh', 'api']:
            endpoint = args[-1]
            if endpoint in self.errors:
                return subprocess.CompletedProcess(args, 1, '', self.errors[endpoint])
            root = f'repos/{r.REPOSITORY}'
            if endpoint == root:
                result = dict(private=True)
            elif endpoint == root + '/git/ref/tags/' + self.spec.tag:
                if self.info['draft']:
                    return subprocess.CompletedProcess(args, 1, '', 'gh: Not Found (HTTP 404)')
                result = dict(object=dict(type='commit', sha=self.spec.commit))
            elif endpoint == root + '/releases/tags/' + self.spec.tag:
                if not self.exists or self.info['draft']:
                    return subprocess.CompletedProcess(args, 1, '', 'gh: Not Found (HTTP 404)')
                result = self.info
            elif endpoint == root + '/releases?per_page=100':
                assert '--paginate' in args and '--slurp' not in args, args
                output = ('\n'.join(json.dumps(page) for page in self.pages)
                          if isinstance(self.pages, list) else json.dumps(self.pages))
                return subprocess.CompletedProcess(args, 0, output, '')
            elif endpoint == root + '/releases/434159539':
                result = self.info
            elif endpoint == root + '/releases/latest':
                result = self.info
            else:
                raise AssertionError(args)
            return subprocess.CompletedProcess(args, 0, json.dumps(result), '')
        if args[:3] == ['gh', 'release', 'create']:
            assert not self.exists, 'must not create when exact draft exists'
            assert '--draft' in args and '--latest=false' in args
            assert args[args.index('--target') + 1] == self.spec.commit
            self.exists = True
            self.pages = [[self.info]]
        elif args[:3] == ['gh', 'release', 'download']:
            name = args[args.index('--pattern') + 1]
            directory = Path(args[args.index('--dir') + 1])
            (directory / name).write_bytes(self.apk if name == self.spec.apk_name else self.metadata)
        elif args[:3] == ['gh', 'release', 'edit']:
            self.info = dict(self.info, draft=False, prerelease='--prerelease=true' in args)
        else:
            raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0, '', '')

    def writes(self):
        return [a for a in self.calls if a[:3] in (['gh', 'release', 'create'], ['gh', 'release', 'edit'])]


class DraftLookupTests(unittest.TestCase):
    def setUp(self):
        self.spec = r.Spec('1.0.8', 8, '2af40ba7c6d027cd5742eed0d558aabef6a27b78', 'a'*64)
        self.api = GithubAPI(self.spec)
        self.gh = r.GithubRelease()
        self.root = f'repos/{r.REPOSITORY}'

    def ensure(self):
        self.gh.ensure(self.spec, b'apk', {})

    def test_exact_draft_on_later_page_is_reused_and_bootstrap_reads_known_id(self):
        with patch.object(r.subprocess, 'run', side_effect=self.api):
            self.ensure()
            before = len(self.api.calls)
            self.gh.activate_bootstrap(self.spec)
        self.assertEqual(len(self.api.writes()), 1)
        self.assertEqual(self.api.writes()[0][:3], ['gh', 'release', 'edit'])
        self.assertIn('--prerelease=true', self.api.writes()[0])
        self.assertIn('--latest=false', self.api.writes()[0])
        later_reads = [a[-1] for a in self.api.calls[before:] if a[:2] == ['gh', 'api']]
        self.assertNotIn(self.root + '/releases/tags/' + self.spec.tag, later_reads)
        self.assertEqual(later_reads.count(self.root + '/releases/434159539'), 2)

    def test_new_draft_hidden_by_tag_endpoint_is_verified_without_second_create(self):
        self.api = GithubAPI(self.spec, exists=False)
        with patch.object(r.subprocess, 'run', side_effect=self.api):
            self.ensure()
        self.assertEqual(len(self.api.writes()), 1)
        self.assertEqual(self.api.writes()[0][:3], ['gh', 'release', 'create'])
        self.assertIn(self.root + '/releases/434159539', [a[-1] for a in self.api.calls])

    def test_standalone_bootstrap_and_legacy_activation_find_hidden_draft(self):
        for method in ('activate_bootstrap', 'activate'):
            with self.subTest(method=method):
                api = GithubAPI(self.spec)
                with patch.object(r.subprocess, 'run', side_effect=api):
                    getattr(r.GithubRelease(), method)(self.spec)
                self.assertEqual(len(api.writes()), 1)
                self.assertIn('--latest=false' if method == 'activate_bootstrap' else '--latest=true', api.writes()[0])

    def test_non404_tag_errors_never_list_or_create(self):
        endpoint = self.root + '/releases/tags/' + self.spec.tag
        for error in ('HTTP 401', 'HTTP 403', 'HTTP 429', 'HTTP 500', 'network failure'):
            with self.subTest(error=error):
                api = GithubAPI(self.spec); api.errors[endpoint] = error
                with patch.object(r.subprocess, 'run', side_effect=api), self.assertRaises(r.Held):
                    self.ensure()
                self.assertFalse(api.writes())
                self.assertNotIn(self.root + '/releases?per_page=100', [a[-1] for a in api.calls])

    def test_list_errors_are_not_absence(self):
        for error in ('HTTP 404', 'HTTP 403', 'HTTP 500', 'network failure'):
            with self.subTest(error=error):
                api = GithubAPI(self.spec); api.errors[self.root + '/releases?per_page=100'] = error
                with patch.object(r.subprocess, 'run', side_effect=api), self.assertRaises(r.Held):
                    self.ensure()
                self.assertFalse(api.writes())

    def test_duplicate_or_malformed_list_never_writes(self):
        for pages in ([[self.api.info], [self.api.info]], {}, [None], [[None]],
                      [[dict(self.api.info, id=True)]], [[dict(self.api.info, url='https://evil.invalid/434159539')]],
                      [[dict(self.api.info, draft=False)]], [[dict(self.api.info, prerelease=0)]]):
            with self.subTest(pages=pages):
                api = GithubAPI(self.spec); api.pages = pages
                with patch.object(r.subprocess, 'run', side_effect=api), self.assertRaises(r.Held):
                    self.ensure()
                self.assertFalse(api.writes())

    def test_wrong_source_and_asset_conflicts_remain_held(self):
        for change in ('source', 'apk', 'metadata'):
            with self.subTest(change=change):
                api = GithubAPI(self.spec)
                if change == 'source': api.info['target_commitish'] = 'b'*40
                elif change == 'apk': api.apk = b'wrong'
                else: api.metadata = b'{"changed":true}'
                with patch.object(r.subprocess, 'run', side_effect=api), self.assertRaises(r.Held):
                    self.ensure()
                self.assertFalse(api.writes())

    def test_published_tag_success_never_lists_and_requires_receipt(self):
        self.api.info.update(draft=False, prerelease=True)
        self.gh.private_mode = True
        self.gh.bootstrap_mode = True  # This case retries the explicitly published bootstrap.
        with patch.object(r.subprocess, 'run', side_effect=self.api):
            with self.assertRaises(r.Held): self.ensure()
            self.gh.allow_published = True
            self.ensure()
        self.assertNotIn(self.root + '/releases?per_page=100', [a[-1] for a in self.api.calls])
        self.assertFalse(self.api.writes())

    def test_unrelated_draft_is_not_selected_when_exact_tag_is_absent(self):
        api = GithubAPI(self.spec, exists=False)
        api.pages = [[dict(api.info, id=7, tag_name='v1.0.7')]]
        with patch.object(r.subprocess, 'run', side_effect=api):
            self.ensure()
        self.assertEqual(len(api.writes()), 1)
        self.assertEqual(api.writes()[0][3], self.spec.tag)

    def test_create_error_or_missing_readback_never_retries(self):
        for failure in ('uncertain create', 'missing readback'):
            with self.subTest(failure=failure):
                api = GithubAPI(self.spec, exists=False)
                def command(args, **kwargs):
                    result = api(args, **kwargs)
                    if args[:3] == ['gh', 'release', 'create']:
                        if failure == 'uncertain create':
                            return subprocess.CompletedProcess(args, 1, '', 'network failure')
                        api.exists = False
                        api.pages = [[]]
                    return result
                with patch.object(r.subprocess, 'run', side_effect=command), self.assertRaises(r.Held):
                    self.ensure()
                self.assertEqual(len(api.writes()), 1)

    def test_invalid_json_or_successful_tag_identity_never_falls_back(self):
        for value in ('not JSON', '{}', '[]', json.dumps(dict(self.api.info, tag_name='v1.0.7'))):
            with self.subTest(value=value):
                api = GithubAPI(self.spec)
                def command(args, **kwargs):
                    result = api(args, **kwargs)
                    if '/releases/tags/' in args[-1]:
                        return subprocess.CompletedProcess(args, 0, value, '')
                    return result
                with patch.object(r.subprocess, 'run', side_effect=command), self.assertRaises(r.Held):
                    self.ensure()
                self.assertFalse(api.writes())
                self.assertNotIn(self.root + '/releases?per_page=100', [a[-1] for a in api.calls])

    def test_partial_paginated_response_is_error_not_absence(self):
        api = GithubAPI(self.spec)
        def command(args, **kwargs):
            result = api(args, **kwargs)
            if args[-1] == self.root + '/releases?per_page=100':
                # gh can emit earlier pages before a later page fails.
                return subprocess.CompletedProcess(args, 1, '[[]]', 'HTTP 500')
            return result
        with patch.object(r.subprocess, 'run', side_effect=command), self.assertRaises(r.Held):
            self.ensure()
        self.assertFalse(api.writes())

    def test_truncated_or_nonarray_pagination_never_authorizes_creation(self):
        for output in ('', '[]\n[', '[]\n{"message":"denied"}', '[]\ngarbage'):
            with self.subTest(output=output):
                api = GithubAPI(self.spec, exists=False)
                def command(args, **kwargs):
                    result = api(args, **kwargs)
                    if args[-1] == self.root + '/releases?per_page=100':
                        result.stdout = output
                    return result
                with patch.object(r.subprocess, 'run', side_effect=command), self.assertRaises(r.Held):
                    self.ensure()
                self.assertFalse(api.writes())

    def test_known_id_identity_drift_or_read_error_never_edits(self):
        for field, value in (('id', 42), ('tag_name', 'v1.0.7'), ('url', 'https://evil.invalid')):
            with self.subTest(field=field):
                api = GithubAPI(self.spec); gh = r.GithubRelease()
                with patch.object(r.subprocess, 'run', side_effect=api):
                    gh.ensure(self.spec, b'apk', {})
                    api.info[field] = value
                    with self.assertRaises(r.Held): gh.activate_bootstrap(self.spec)
                self.assertFalse(api.writes())
        with patch.object(r.subprocess, 'run', side_effect=self.api):
            self.ensure()
            self.api.errors[self.root + '/releases/434159539'] = 'HTTP 404'
            with self.assertRaises(r.Held): self.gh.activate_bootstrap(self.spec)
        self.assertFalse(self.api.writes())
