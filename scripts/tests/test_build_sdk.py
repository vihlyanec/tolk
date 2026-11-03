import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('verify_build_sdk', Path(__file__).resolve().parents[1] / 'verify_build_sdk.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class BuildSDKTests(unittest.TestCase):
    def build(self, sdk='27.0', minimum='14.0'):
        return dict(platform='MACOS',minimum_os=minimum,sdk=sdk)
    def test_sdk_is_independent_of_compatibility_version(self):
        builds={arch:self.build() for arch in ['arm64','x86_64']}
        self.assertEqual(module.validate_versions(builds,'27.0.0',universal=True),builds)
    def test_old_universal_sdk_regression_blocks_packaging(self):
        for arch in ['arm64','x86_64']:
            builds={name:self.build() for name in ['arm64','x86_64']}
            builds[arch]=self.build('14.0')
            with self.subTest(arch=arch), self.assertRaisesRegex(ValueError,'неверная метка SDK'):
                module.validate_versions(builds,'27.0',universal=True)
    def test_missing_slice_or_changed_minimum_cannot_pass(self):
        with self.assertRaises(ValueError): module.validate_versions({'arm64':self.build()},'27.0',universal=True)
        with self.assertRaises(ValueError): module.validate_versions({'arm64':self.build(minimum='27.0')},'27.0')
        with self.assertRaises(ValueError): module.validate_versions({},'27.0')
    def test_vtool_parser_rejects_missing_or_ambiguous_metadata(self):
        text='''binary (architecture arm64):\nLoad command 11\n      cmd LC_BUILD_VERSION\n platform MACOS\n    minos 14.0\n      sdk 27.0\n   ntools 1\n'''
        self.assertEqual(module.parse_build_version(text),self.build())
        for invalid in ['',text.replace('sdk 27.0','sdk unknown'),text+text]:
            with self.subTest(text=invalid), self.assertRaises(ValueError):
                value=module.parse_build_version(invalid)
                module.validate_versions({'arm64':value},'27.0')
