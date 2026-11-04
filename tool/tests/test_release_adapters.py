"""Adapter tests: controlled commands/clients, NOT real APK or cloud verification."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_release as r
from test_github_draft_lookup import GithubAPI

class AdapterTests(unittest.TestCase):
    def setUp(self): self.spec = r.Spec('1.0.5', 6, 'b'*40, 'a'*64)
    def cert(self, signer=None):
        return 'Signer #1 certificate SHA-256 digest: ' + (signer or self.spec.signer) + '\n'
    def badge(self, package=r.PACKAGE):
        return f"package: name='{package}' versionCode='6' versionName='1.0.5'\n"
    def test_apk_verifier_real_subprocess_with_controlled_tools(self):
        with tempfile.TemporaryDirectory() as tmp:
            tools = []
            for name, output in [('apksigner',self.cert()), ('aapt',self.badge())]:
                path = Path(tmp) / name
                path.write_text('#!/usr/bin/env python3\nprint(' + repr(output) + ')\n')
                path.chmod(0o700); tools.append(str(path))
            r.ApkVerifier(*tools)(b'fixture bytes only', self.spec)
    def test_verifier_rejects_wrong_signer_package_multiple_signers_debug_and_tool_failure(self):
        for cert, badge in [(self.cert('d'*64),self.badge()),
                            (self.cert(),self.badge('other')),
                            (self.cert()+self.cert(),self.badge()),
                            (self.cert()+'CN=Android Debug',self.badge())]:
            with self.subTest(cert=cert):
                with patch.object(r, 'run', side_effect=[cert,badge]):
                    with self.assertRaises(r.Held): r.ApkVerifier('signer','aapt')(b'x',self.spec)
        with patch.object(r.subprocess,'run',return_value=subprocess.CompletedProcess([],1,'','private secret')):
            with self.assertRaisesRegex(r.Held,'^external verification/asset command failed$'): r.run(['signer'])
    def test_apksigner37_scheme_labels_and_rotation_refusal(self):
        same = 'Number of signers: 1\nV2 Signer: certificate SHA-256 digest: '+self.spec.signer+'\n'
        with patch.object(r,'run',side_effect=[same,self.badge()]):
            r.ApkVerifier('signer','aapt')(b'x',self.spec)
        both = same+'V3 Signer: certificate SHA-256 digest: '+self.spec.signer+'\n'
        with patch.object(r,'run',side_effect=[both,self.badge()]):
            r.ApkVerifier('signer','aapt')(b'x',self.spec)
        for bad in [both.replace('V3 Signer: certificate SHA-256 digest: '+self.spec.signer,'V3 Signer: certificate SHA-256 digest: '+'b'*64),
                    same.replace('Number of signers: 1','Number of signers: 2'),same+same,
                    same.replace('Number of signers: 1\n','')]:
            with patch.object(r,'run',return_value=bad),self.assertRaises(r.Held):
                r.ApkVerifier('signer','aapt')(b'x',self.spec)

    def test_s3_conditional_create_and_exact_readback(self):
        try:
            import botocore
        except ImportError:
            self.skipTest('botocore not installed; adapter optional')
        class Client:
            kwargs = None
            def put_object(inner, **kw): inner.kwargs=kw
            def get_object(inner, **kw):
                import io
                return {'Body':io.BytesIO(b'apk')}
        client = Client(); storage = r.S3Storage(client,'approved-test-bucket')
        storage.put_if_absent('key',b'apk')
        self.assertEqual(client.kwargs['IfNoneMatch'],'*')
        self.assertEqual(client.kwargs['Body'],b'apk')
        self.assertEqual(storage.read('key'),b'apk')
    def test_boto3_against_loopback_conditional_http_server(self):
        try:
            import boto3
            from botocore.config import Config
        except ImportError:
            self.skipTest('boto3 not installed; optional HTTP adapter rehearsal')
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        import threading
        objects = {}
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_PUT(self):
                data = self.rfile.read(int(self.headers['Content-Length']))
                requests.append(('PUT',self.headers.get('If-None-Match')))
                if self.headers.get('If-None-Match') != '*' or self.path in objects:
                    self.send_response(412); self.end_headers(); return
                objects[self.path] = data
                self.send_response(200); self.send_header('Content-Length','0'); self.end_headers()
            def do_GET(self):
                data=objects[self.path]
                requests.append(('GET',None))
                self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers()
                self.wfile.write(data)
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        try:
            client=boto3.client('s3',endpoint_url=f'http://127.0.0.1:{server.server_port}',
                region_name='us-east-1',aws_access_key_id='SYNTHETIC',aws_secret_access_key='SYNTHETIC',
                config=Config(s3={'addressing_style':'path'},retries={'max_attempts':0}))
            storage=r.S3Storage(client,'test-mobile')
            storage.put_if_absent('immutable.apk',b'original')
            self.assertEqual(storage.read('immutable.apk'),b'original')
            storage.put_if_absent('immutable.apk',b'replacement')
            self.assertEqual(storage.read('immutable.apk'),b'original')
            self.assertEqual(requests,[('PUT','*'),('GET',None),('PUT','*'),('GET',None)])
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_s3_412_allowed_only_for_readback_other_errors_fail(self):
        try:
            from botocore.exceptions import ClientError
        except ImportError: self.skipTest('botocore not installed; adapter optional')
        class Client:
            def put_object(inner, **kw):
                raise ClientError({'ResponseMetadata':{'HTTPStatusCode':inner.code}},'PutObject')
        client=Client(); storage=r.S3Storage(client,'approved-test-bucket')
        for code in [403,409,500]:
            client.code=code
            with self.assertRaises(r.Held): storage.put_if_absent('key',b'apk')
        client.code=412; storage.put_if_absent('key',b'apk')
    def test_tag_resolution_lightweight_and_annotated(self):
        for obj in [{'type':'commit','sha':self.spec.commit}, {'type':'tag','sha':'c'*40}]:
            cp=subprocess.CompletedProcess([],0,json.dumps({'object':obj}),'')
            with patch.object(r.subprocess,'run',return_value=cp), patch.object(r,'run',return_value=json.dumps({'object':{'type':'commit','sha':self.spec.commit}})):
                self.assertEqual(r.GithubRelease().tag_commit(self.spec), self.spec.commit)
    def test_wrong_existing_tag_blocks_creation(self):
        gh=r.GithubRelease()
        with patch.object(gh,'tag_commit',return_value='d'*40), patch.object(r.subprocess,'run') as command:
            with self.assertRaises(r.Held): gh.ensure(self.spec,b'apk',{})
            command.assert_not_called()
    def test_github_existing_exact_assets_rerun_and_conflict(self):
        gh=r.GithubRelease(); api=GithubAPI(self.spec)
        with patch.object(r.subprocess, 'run', side_effect=api):
            gh.ensure(self.spec,b'apk',{})
            gh.ensure(self.spec,b'apk',{})
            api.apk = b'wrong'
            with self.assertRaises(r.Held): gh.ensure(self.spec,b'apk',{})
        self.assertFalse(api.writes())

    def test_new_github_release_is_draft_not_latest_until_activation(self):
        gh=r.GithubRelease(); api=GithubAPI(self.spec, exists=False)
        with patch.object(r.subprocess, 'run', side_effect=api):
            gh.ensure(self.spec,b'apk',{})
            created=api.writes()[0]
            self.assertIn('--draft',created)
            self.assertIn('--latest=false',created)
        public=GithubAPI(self.spec); public.info.update(draft=False, prerelease=False)
        with patch.object(r.subprocess, 'run', side_effect=public):
            with self.assertRaises(r.Held): r.GithubRelease().ensure(self.spec,b'apk',{})

    def test_activation_checks_exact_latest_and_source_readback(self):
        gh=r.GithubRelease(); api=GithubAPI(self.spec)
        with patch.object(r.subprocess, 'run', side_effect=api):
            gh.activate(self.spec)
        self.assertIn('--latest=true',api.writes()[0])
        api=GithubAPI(self.spec)
        def wrong_latest(args, **kwargs):
            result = api(args, **kwargs)
            if args[-1].endswith('/releases/latest'):
                result.stdout = json.dumps(dict(api.info, tag_name='wrong'))
            return result
        with patch.object(r.subprocess, 'run', side_effect=wrong_latest):
            with self.assertRaises(r.Held): r.GithubRelease().activate(self.spec)

    def test_cli_missing_configuration_is_held_without_secret_output(self):
        script = Path(__file__).resolve().parents[1] / 'mobile_release.py'
        result=subprocess.run([sys.executable,str(script),'--apk','unused','--metadata','unused','--apksigner','unused','--aapt','unused'],env={'GITHUB_EVENT_NAME':'pull_request'},capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertIn('HELD',result.stderr)
        self.assertNotIn('Traceback',result.stderr)

class WorkflowPolicyTests(unittest.TestCase):
    def test_publication_is_main_only_manual_protected_and_not_web_dependent(self):
        path=Path(__file__).resolve().parents[2] / '.github/workflows/flutter.yml'
        text=path.read_text()
        release=text.split('\n  release:\n')[1]
        self.assertIn("github.event_name == 'push'", release)
        self.assertIn("github.ref == 'refs/heads/main'", release)
        self.assertIn('inputs.publish_android == true', release)
        self.assertIn('environment: mobile-release',release)
        self.assertIn('needs: [checks, release-tooling, build]',release)
        self.assertNotIn('needs: web',release)
        self.assertNotIn('tags:',text)
        self.assertIn('cancel-in-progress: false',text)
        self.assertNotIn('--clobber',text)
        for line in text.splitlines():
            if '--dart-define' in line:
                self.assertNotIn('REGISTRY_DSN',line); self.assertNotIn('SECRET_ACCESS',line)
