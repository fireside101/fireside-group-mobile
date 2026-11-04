"""Offline CI runtime policy; action majors verified against upstream action.yml."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / '.github' / 'workflows'
# Each current upstream major uses node24 (not the Node installed for app tests).
# Reviewed releases: checkout v7.0.1, upload-artifact v7.0.2,
# download-artifact v8.0.2, setup-java v6.1.0, setup-python/setup-node v7.1.0.
# Sources: https://github.com/actions/<action>/releases and the corresponding
# https://github.com/actions/<action>/blob/<tag>/action.yml (runs.using).
# Ubuntu image: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
ACTION_MAJORS = {
    'checkout': 'v7',
    'upload-artifact': 'v7',
    'download-artifact': 'v8',
    'setup-java': 'v6',
    'setup-python': 'v7',
    'setup-node': 'v7',
}


class WorkflowRuntimeTests(unittest.TestCase):
    def test_all_first_party_actions_use_reviewed_node24_majors(self):
        seen = set()
        for path in sorted(WORKFLOWS.glob('*.y*ml')):
            for action, version in re.findall(r'uses:\s*actions/([\w-]+)@([^\s#]+)', path.read_text()):
                with self.subTest(workflow=path.name, action=action):
                    self.assertIn(action, ACTION_MAJORS)
                    self.assertEqual(version, ACTION_MAJORS[action])
                    seen.add(action)
        self.assertEqual(seen, set(ACTION_MAJORS))

    def test_all_jobs_pin_supported_ubuntu_24_04(self):
        paths = sorted(WORKFLOWS.glob('*.y*ml'))
        self.assertTrue(paths)
        for path in paths:
            runners = re.findall(r'^\s*runs-on:\s*(\S+)\s*$', path.read_text(), re.M)
            with self.subTest(workflow=path.name):
                self.assertTrue(runners)
                self.assertEqual(set(runners), {'ubuntu-24.04'})

    def test_sdk_versions_and_no_implicit_node_package_cache(self):
        text = (WORKFLOWS / 'flutter.yml').read_text()
        self.assertIn("FLUTTER_VERSION: '3.47.4'", text)
        self.assertIn("node-version: '22'", text)
        self.assertIn('package-manager-cache: false', text)
        self.assertNotIn('FORCE_JAVASCRIPT_ACTIONS_TO_NODE24', text)
        for path in WORKFLOWS.glob('*.y*ml'):
            for block in re.split(r'\n\s*- uses:', path.read_text()):
                if block.lstrip().startswith('actions/setup-java@'):
                    self.assertIn("java-version: '17'", block)
                if block.lstrip().startswith('actions/setup-python@'):
                    self.assertIn("python-version: '3.12'", block)
