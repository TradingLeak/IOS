"""Synthetic IPA fixtures only; no signing credentials or actual app binaries."""
import hashlib
import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify", Path(__file__).with_name("verify-ipa.py"))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class IPAAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "Example.ipa"

    def make(self, platform=2, cpu=0x0100000C, cryptid=0, mode=0o100755, prefix="Payload/Example.app", executable=True):
        info = dict(CFBundleIdentifier="com.example.audit", CFBundleExecutable="Example", CFBundleName="Example",
                    CFBundleShortVersionString="1.0.0", CFBundleVersion="1", CFBundlePackageType="APPL",
                    CFBundleSupportedPlatforms=["iPhoneOS"], MinimumOSVersion="16.0")
        commands = struct.pack("<6I", 0x32, 24, platform, 16 << 16, 16 << 16, 0)
        commands += struct.pack("<6I", 0x2C, 24, 0, 0, cryptid, 0)
        macho = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 2, len(commands), 0, 0) + commands
        with zipfile.ZipFile(self.path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(prefix + "/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            if executable:
                entry = zipfile.ZipInfo(prefix + "/Example")
                entry.create_system = 3
                entry.external_attr = mode << 16
                archive.writestr(entry, macho)
        return self.path

    def test_valid_device_archive(self):
        result = verify.inspect(self.make())
        self.assertEqual(result["result"], "PASS")
        self.assertEqual(result["architecture"], "arm64")
        self.assertEqual(result["platform"], "IOS")
        self.assertFalse(result["encrypted"])
        self.assertFalse(result["has_code_signature_command"])

    def test_simulator_rejected(self):
        with self.assertRaises(verify.IPAError):
            verify.inspect(self.make(platform=7))

    def test_non_arm64_rejected(self):
        with self.assertRaises(verify.IPAError):
            verify.inspect(self.make(cpu=0x01000007))

    def test_encrypted_executable_rejected(self):
        with self.assertRaises(verify.IPAError):
            verify.inspect(self.make(cryptid=1))

    def test_missing_executable_or_execute_bits(self):
        for kwargs in ({"executable": False}, {"mode": 0o100644}):
            with self.subTest(kwargs=kwargs), self.assertRaises(verify.IPAError):
                verify.inspect(self.make(**kwargs))

    def test_outer_artifact_zip_or_wrong_payload_rejected(self):
        with self.assertRaises(verify.IPAError):
            verify.inspect(self.make(prefix="dist/Payload/Example.app"))

    def test_html_download_is_not_an_ipa(self):
        self.path.write_text("<html>Not Found</html>")
        with self.assertRaises(verify.IPAError):
            verify.inspect(self.path)

    def test_published_checksum(self):
        self.make()
        sha = hashlib.sha256(self.path.read_bytes()).hexdigest()
        self.assertEqual(verify.inspect(self.path, sha)["sha256"], sha)
        with self.assertRaises(verify.IPAError):
            verify.inspect(self.path, "0" * 64)


if __name__ == "__main__":
    unittest.main()
