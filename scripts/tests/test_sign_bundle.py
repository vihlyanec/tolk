import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sign_bundle', Path(__file__).resolve().parents[1] / 'sign_bundle.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class ApplicationSigningTests(unittest.TestCase):
    def test_designated_requirement_accepts_both_streams_and_requires_signer(self):
        stable = 'designated => identifier "local.takt.mac" and certificate leaf = H"abc"'
        self.assertEqual(module.designated_requirement(stable, 'Executable=app'), stable.split('=>', 1)[1].strip())
        self.assertEqual(module.designated_requirement('', stable), stable.split('=>', 1)[1].strip())
        for value in ['designated => cdhash H"abc"', 'designated => identifier "local.takt.mac"', '']:
            with self.assertRaises(ValueError): module.designated_requirement(value, '')
    def test_release_uses_pinned_identity_and_dev_stays_isolated(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            config = Path(directory) / 'app-signing.json'
            config.write_text(json.dumps(dict(identity_sha1='A'*40, certificate_sha256='b'*64, name='Tolk Application Signing')))
            self.assertEqual(module.identity_for(True, config), 'A'*40)
            self.assertEqual(module.identity_for(False, config), '-')
            with patch.dict(os.environ, TOLK_CODE_SIGN_IDENTITY='-'):
                with self.assertRaises(ValueError): module.identity_for(True, config)
            with patch.dict(os.environ, TOLK_CODE_SIGN_IDENTITY='B'*40):
                with self.assertRaises(ValueError): module.identity_for(True, config)

    def test_invalid_config_never_falls_back_to_ad_hoc(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            config = Path(directory) / 'app-signing.json'
            with self.assertRaises(ValueError): module.identity_for(True, config)
            self.assertEqual(module.identity_for(False, config), '-')
            for value in ['-', 'Tolk Application Signing', 'a'*40]:
                config.write_text(json.dumps(dict(identity_sha1=value, certificate_sha256='b'*64)))
                with self.assertRaises(ValueError): module.identity_for(True, config)
