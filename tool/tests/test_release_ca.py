"""Runner CA provisioning: approved public PEM only, no TLS downgrade."""
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_release as r


class RegistryCATests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        root = Path(cls.temp.name)
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-days', '1', '-subj', '/CN=Synthetic release CA',
                        '-keyout', str(root/'key'), '-out', str(root/'ca')],
                       check=True, capture_output=True)
        cls.pem = (root/'ca').read_text()

    def test_provisions_real_certificate_at_dsn_path(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'mobile-registry-ca.pem'
            env = dict(RUNNER_TEMP=temp, MOBILE_REGISTRY_CA_PEM=self.pem,
                       MOBILE_REGISTRY_DSN=f'host=registry.example sslmode=verify-full sslrootcert={path}')
            r.prepare_registry_ca(env)
            self.assertEqual(path.read_text(), self.pem)
            ssl.create_default_context(cafile=str(path))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_invalid_ca_payload_and_dsn_never_create_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'mobile-registry-ca.pem'
            env = dict(RUNNER_TEMP=temp, MOBILE_REGISTRY_CA_PEM=self.pem,
                       MOBILE_REGISTRY_DSN=f'host=registry.example sslmode=verify-full sslrootcert={path}')
            for change in [dict(MOBILE_REGISTRY_CA_PEM=''),
                           dict(MOBILE_REGISTRY_CA_PEM=self.pem.replace('\n', r'\n')),
                           dict(MOBILE_REGISTRY_CA_PEM=self.pem+'-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----'),
                           dict(MOBILE_REGISTRY_CA_PEM='-----BEGIN CERTIFICATE-----\nnot-a-cert\n-----END CERTIFICATE-----\n'),
                           dict(MOBILE_REGISTRY_DSN='host=registry.example sslmode=require'),
                           dict(MOBILE_REGISTRY_DSN='host=registry.example sslmode=verify-full sslrootcert=/other/ca.pem')]:
                with self.subTest(change=list(change)), self.assertRaises(r.Held):
                    r.prepare_registry_ca(dict(env, **change))
                self.assertFalse(path.exists())

    def test_workflow_provisions_ca_in_each_job_before_registry_access(self):
        text = (Path(__file__).resolve().parents[2]/'.github/workflows/flutter.yml').read_text()
        for job, access in [('build', '--allocate'), ('release', '--apk')]:
            part = text.split('\n  '+job+':\n')[1].split('\n  web:\n')[0]
            self.assertLess(part.index('--prepare-registry-ca'), part.index(access))
            self.assertIn('MOBILE_REGISTRY_CA_PEM: ${{ vars.MOBILE_REGISTRY_CA_PEM }}', part)
        for line in text.splitlines():
            if '--dart-define' in line:
                for prohibited in ('REGISTRY_DSN','STORAGE_TOKEN','CA_PEM','KEYSTORE','SECRET_ACCESS'):
                    self.assertNotIn(prohibited, line)
