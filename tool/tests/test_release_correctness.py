"""Automatic release and discovery safety, offline deterministic tests."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_release as r
import test_mobile_release as base
from unittest.mock import patch
import json
import subprocess
import tempfile

class RetryTests(unittest.TestCase):
    def test_retry_reuses_original_bytes_and_only_404_permits_rebuild(self):
        spec=r.Spec('1.0.6',6,'b'*40,'a'*64)
        for status, stderr in [(1,'HTTP 403'),(1,'timeout')]:
            with patch.object(r.subprocess,'run',return_value=subprocess.CompletedProcess([],status,'',stderr)):
                with self.assertRaises(r.Held): r.reuse_original(spec, Path('unused'))
        with patch.object(r.subprocess,'run',return_value=subprocess.CompletedProcess([],1,'','HTTP 404')):
            self.assertFalse(r.reuse_original(spec,Path('unused')))
        with tempfile.TemporaryDirectory() as tmp:
            cp=subprocess.CompletedProcess([],0,json.dumps({'target_commitish':spec.commit}),'')
            with patch.object(r.subprocess,'run',return_value=cp), patch.object(r.GithubRelease,'_download',side_effect=[b'original-apk',b'{}']):
                self.assertTrue(r.reuse_original(spec,Path(tmp)))
                self.assertEqual((Path(tmp)/spec.apk_name).read_bytes(),b'original-apk')


class DiscoveryTests(base.PublisherTests):
    def setUp(self):
        super().setUp()
        self.github.activate = lambda spec: self.registry.events.append('activate')
    def test_success_order_exact_bytes_and_readback(self):
        self.publish()
        self.assertEqual(self.registry.events, ['reserve','github','download','s3','advertise','activate'])
    def test_receipt_failure_never_activates_legacy_latest(self):
        self.registry.read = lambda commit: None
        with self.assertRaises(r.Held): self.publish()
        self.assertNotIn('activate', self.registry.events)
    def test_numeric_representation_drift_in_receipt_cannot_activate(self):
        self.registry.read = lambda commit: dict(self.registry.payload, version_code=float(self.spec.code))
        with self.assertRaises(r.Held): self.publish()
        self.assertNotIn('activate', self.registry.events)

    def test_stale_or_revoked_registry_pointer_never_reactivates_legacy(self):
        self.registry.read_latest = lambda: None
        with self.assertRaises(r.Held): self.publish()
        self.assertNotIn('activate', self.registry.events)

    def test_storage_failure_never_activates_legacy_latest(self):
        self.storage.put_if_absent = lambda *args: (_ for _ in ()).throw(r.Held('held'))
        with self.assertRaises(r.Held): self.publish()
        self.assertNotIn('activate', self.registry.events)

class AdmissionTests(unittest.TestCase):
    def test_workflow_condition_matrix_executes_no_pr_dev_or_tag_publish(self):
        import re
        import ast
        text=(Path(__file__).resolve().parents[2]/'.github/workflows/flutter.yml').read_text()
        for job in ['build','release']:
            expr=re.search(r'^    if: (.*)$',text.split('\n  '+job+':\n')[1],re.M)[1]
            from itertools import product
            for actor, triggering in product(['josephndex','contributor','unknown',''], repeat=2):
                for event, ref, manual, allowed in [
                    ('push','refs/heads/main',False,True),
                    ('push','refs/heads/dev',True,False),
                    ('pull_request','refs/heads/main',True,False),
                    ('push','refs/tags/v1.0.6',True,False),
                    ('workflow_dispatch','refs/heads/main',False,False),
                    ('workflow_dispatch','refs/heads/main',True,True),
                ]:
                    candidate=expr.replace('github.triggering_actor',repr(triggering)).replace('github.actor',repr(actor)).replace('github.event_name',repr(event)).replace('github.ref',repr(ref)).replace('inputs.publish_android',repr(manual)).replace('true','True').replace('false','False').replace('&&',' and ').replace('||',' or ')
                    tree=ast.parse(candidate,mode='eval')
                    self.assertTrue(all(isinstance(n,(ast.Expression,ast.BoolOp,ast.And,ast.Or,ast.Compare,ast.Eq,ast.Constant)) for n in ast.walk(tree)))
                    # No calls/names/attributes or configurable actor overrides.
                    expected = allowed and actor == triggering == 'josephndex'
                    self.assertEqual(eval(compile(tree,'condition','eval'),{'__builtins__':{}}),expected,(job,event,ref,manual,actor,triggering))

    def test_allocate_cli_writes_identical_build_and_metadata_inputs(self):
        import os
        from contextlib import chdir
        env={'GITHUB_REF':'refs/heads/main','GITHUB_EVENT_NAME':'push',
             'GITHUB_SHA':'b'*40,'MOBILE_RELEASE_APPROVED':'true',
             'GITHUB_ACTOR':'josephndex','GITHUB_TRIGGERING_ACTOR':'josephndex',
             'MOBILE_PRODUCTION_SIGNER_SHA256':'a'*64,
             'MOBILE_REGISTRY_CONTRACT':'mobile_release_v1', 'MOBILE_STORAGE_PROVIDER':'s3'}
        class Registry:
            def allocate(inner, commit, version, signer):
                self.assertEqual((commit,version,signer),('b'*40,'1.0.4','a'*64))
                return {'code':6,'version_name':'1.0.6'}
        with tempfile.TemporaryDirectory() as tmp, chdir(tmp):
            Path('pubspec.yaml').write_text('name: fireside_group\nversion: 1.0.4+5\n')
            env['GITHUB_ENV']=str(Path(tmp)/'output')
            with patch.dict(os.environ,env,clear=True), patch.object(sys,'argv',['release','--allocate']), patch.object(r,'verify_environment'), patch.object(r,'run',side_effect=['b'*40,'','b'*40]), patch.object(r.PostgresRegistry,'from_environment',return_value=Registry()):
                r.main()
            self.assertIn('version: 1.0.6+6',Path('pubspec.yaml').read_text())
            self.assertEqual(Path('output').read_text(),'MOBILE_BUILD_CODE=6\nMOBILE_BUILD_NAME=1.0.6\n')

    def test_only_approved_main_push_or_explicit_manual(self):
        base = dict(GITHUB_REF='refs/heads/main', MOBILE_RELEASE_APPROVED='true',
                    GITHUB_ACTOR='josephndex', GITHUB_TRIGGERING_ACTOR='josephndex')
        for event in ['push','workflow_dispatch']:
            env = dict(base, GITHUB_EVENT_NAME=event, MOBILE_PUBLISH_ANDROID='true')
            r.admit(env)
        for env in [dict(base,GITHUB_EVENT_NAME='pull_request'),
                    dict(base,GITHUB_EVENT_NAME='push',GITHUB_REF='refs/heads/dev'),
                    dict(base,GITHUB_EVENT_NAME='workflow_dispatch'),
                    dict(GITHUB_EVENT_NAME='push',GITHUB_REF='refs/heads/main')]:
            with self.assertRaises(r.Held): r.admit(env)
    def test_protection_is_not_an_environment_label_or_boolean(self):
        valid = {'can_admins_bypass':False,
                 'deployment_branch_policy':{'protected_branches':False,'custom_branch_policies':True},
                 'protection_rules':[]}
        r.check_protection(valid, {'branch_policies':[{'name':'main','type':'branch'}], 'total_count':1})
        for env, branches in [({},{}),(dict(valid,can_admins_bypass=True),{}),
                              (dict(valid,deployment_branch_policy={'protected_branches':True,'custom_branch_policies':False}),{}),
                              (valid,{'branch_policies':[{'name':'*','type':'branch'}],'total_count':1})]:
            with self.assertRaises(r.Held): r.check_protection(env, branches)
    def test_both_original_and_rerunning_actors_must_be_approved(self):
        valid = dict(GITHUB_REF='refs/heads/main', GITHUB_EVENT_NAME='push',
                     MOBILE_RELEASE_APPROVED='true', GITHUB_ACTOR='josephndex',
                     GITHUB_TRIGGERING_ACTOR='josephndex')
        for field in ('GITHUB_ACTOR', 'GITHUB_TRIGGERING_ACTOR'):
            for actor in ('', 'unknown', 'contributor', 'Josephndex'):
                with self.subTest(field=field, actor=actor), self.assertRaises(r.Held):
                    r.admit(dict(valid, **{field:actor}, MOBILE_APPROVED_ACTOR=actor))

    def test_main_only_environment_rejects_weakened_or_manual_gate_policy(self):
        valid = dict(can_admins_bypass=False, protection_rules=[],
                     deployment_branch_policy=dict(protected_branches=False,custom_branch_policies=True))
        branches = dict(total_count=1,branch_policies=[dict(name='main',type='branch')])
        for info, rules in [
            (dict(valid,can_admins_bypass=True),branches),
            (dict(valid,deployment_branch_policy=None),branches),
            (valid,dict(total_count=2,branch_policies=[dict(name='main',type='branch')])),
            (valid,dict(total_count=1,branch_policies=[dict(name='main',type='tag')])),
            (valid,dict(total_count=1,branch_policies=[dict(name='*',type='branch')])),
            (dict(valid,protection_rules=[dict(type='required_reviewers',reviewers=[dict(id=1)])]),branches),
        ]:
            with self.subTest(info=info,rules=rules), self.assertRaises(r.Held):
                r.check_protection(info,rules)
    def test_workflow_allocates_before_build_and_push_publishes(self):
        text=(Path(__file__).resolve().parents[2]/'.github/workflows/flutter.yml').read_text()
        self.assertIn("github.event_name == 'push'", text.split('\n  release:\n')[1])
        self.assertLess(text.index('--allocate'),text.index('flutter build apk'))
        self.assertIn('--build-number="$MOBILE_BUILD_CODE"',text)
        self.assertIn('--build-name="$MOBILE_BUILD_NAME"',text)
