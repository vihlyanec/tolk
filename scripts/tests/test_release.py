import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('configure_bundle', SCRIPTS / 'configure_bundle.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class ReleaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = self.root / 'updates.json'
        self.public = base64.b64encode(bytes(range(32))).decode()
        self.config.write_text(json.dumps(dict(repository='test-owner/tolk', public_key=self.public, keychain_account='tolk-updates')))
        self.bundle = self.root / 'Толк.app'
        (self.bundle / 'Contents').mkdir(parents=True)
        (self.bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.takt.mac','CFBundleVersion':'22','CFBundleShortVersionString':'0.9.3'}))
    def tearDown(self): self.temp.cleanup()
    def test_release_embeds_only_public_configuration_and_requires_signatures(self):
        with patch.dict(os.environ, TOLK_RELEASE_CONFIG=str(self.config), TOLK_VERSION='1.0.0', TOLK_BUILD='23'):
            module.configure(self.bundle, True)
        value = plistlib.loads((self.bundle / 'Contents/Info.plist').read_bytes())
        self.assertEqual(value['SUFeedURL'],'https://github.com/test-owner/tolk/releases/latest/download/appcast.xml')
        self.assertEqual(value['SUPublicEDKey'], self.public)
        self.assertTrue(value['SURequireSignedFeed'] and value['SUVerifyUpdateBeforeExtraction'])
        self.assertFalse(value['SUAllowsAutomaticUpdates'] or value['SUSendProfileInfo'])
        self.assertEqual(value['CFBundleVersion'],'23')
        self.assertEqual(value['CFBundleIdentifier'],'local.takt.mac')
    def test_development_build_has_no_feed(self):
        module.configure(self.bundle)
        self.assertNotIn('SUFeedURL', plistlib.loads((self.bundle / 'Contents/Info.plist').read_bytes()))
    def test_placeholder_or_malformed_repository_and_keys_are_rejected(self):
        for repo,key in [('YOUR NAME/tolk', self.public), ('https://github.com/a/b', self.public), ('a/b', 'not-a-key')]:
            self.config.write_text(json.dumps(dict(repository=repo, public_key=key)))
            with self.assertRaises(ValueError): module.read_configuration(self.config)
    def test_missing_configuration_cannot_make_release(self):
        with patch.dict(os.environ, TOLK_RELEASE_CONFIG=str(self.root / 'missing.json')):
            with self.assertRaises(ValueError): module.configure(self.bundle, True)

class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        import sys
        if str(SCRIPTS) not in sys.path: sys.path.insert(0, str(SCRIPTS))
        import release
        self.release = release
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.folder = self.root/'v1.0.0'; self.folder.mkdir()
        self.config = dict(repository='test-owner/tolk',public_key='test-key')
    def tearDown(self): self.temp.cleanup()
    def test_test_build_is_rejected_before_github_is_contacted(self):
        (self.folder/'manifest.json').write_text(json.dumps(dict(self.config,sha256={},test_build=True,source_clean=False)))
        with patch.object(self.release,'RELEASES',self.root), patch.object(self.release,'read_configuration',return_value=self.config), patch.object(self.release,'github') as github:
            with self.assertRaises(ValueError): self.release.upload('1.0.0')
            with self.assertRaises(ValueError): self.release.publish('1.0.0')
            github.assert_not_called()
    def test_modified_archive_cannot_be_uploaded(self):
        import hashlib
        archive = self.folder/'Tolk-1.0.0.zip'; archive.write_bytes(b'original')
        (self.folder/'manifest.json').write_text(json.dumps(dict(self.config,sha256={archive.name:hashlib.sha256(b'original').hexdigest()})))
        self.release.verify_manifest(self.folder,self.config)
        archive.write_bytes(b'changed')
        with self.assertRaises(ValueError): self.release.verify_manifest(self.folder,self.config)

    def test_draft_lookup_does_not_require_a_published_tag(self):
        draft = dict(id=123,tag_name='v1.0.0',draft=True,assets=[])
        with patch.object(self.release,'github',return_value=json.dumps([[dict(tag_name='v0.9.0')],[draft]])) as github:
            result = self.release.find_release(self.config,'1.0.0')
            self.assertEqual(result,draft)
            self.assertIn('--paginate',github.call_args.args[0])
            self.assertNotIn('/tags/',github.call_args.args[0][1])

if __name__ == '__main__': unittest.main()
