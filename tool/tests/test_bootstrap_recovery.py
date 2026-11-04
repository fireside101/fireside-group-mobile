import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import recover_bootstrap as recovery
import mobile_release as r

class RecoveryTests(unittest.TestCase):
    def test_exact_source_only_allows_recovery_files(self):
        for changed,ok in [('',True),('tool/recover_bootstrap.py\n',True),('lib/main.dart\n',False),('tool/mobile_release.py\n',False)]:
            with patch.dict(recovery.os.environ,{'GITHUB_SHA':'a'*40}),patch.object(r,'run',side_effect=['a'*40,'a'*40,changed]):
                if ok: recovery.source_guard()
                else:
                    with self.assertRaises(r.Held):recovery.source_guard()
        with patch.dict(recovery.os.environ,{'GITHUB_SHA':'b'*40}),patch.object(r,'run',return_value='a'*40),self.assertRaises(r.Held):
            recovery.source_guard()
    def test_diagnostic_never_reflects_stderr(self):
        for args,label in [(['apksigner','verify'],'apksigner'),(['gh','release','create'],'gh_release_create'),(['gh','api','private'],'gh_api')]:
            with patch.object(subprocess,'run',return_value=subprocess.CompletedProcess(args,1,'','sensitive token HTTP 403')):
                with self.assertRaisesRegex(r.Held,'^recovery_'+label+'_http_403$'):
                    recovery.diagnostic_run(args)
    def test_diagnostic_success_preserves_real_command_output(self):
        with patch.object(subprocess,'run',return_value=subprocess.CompletedProcess([],0,'ok','')):
            self.assertEqual(recovery.diagnostic_run(['git','rev-parse','HEAD']),'ok')
    def test_retained_identity_is_frozen(self):
        self.assertEqual(recovery.SOURCE,'cd65ca3be70fbab17e9b492fa1aa9a47c4742418')
        self.assertEqual(recovery.SHA,'d177f653c3dbc60057577336c6dd47c0babcea2e88344d79e4b57e4b0f4f0de6')
