"""Executable checks for release-packaging input validation."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
PUBLIC_KEY = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="


class UpdatePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "script").mkdir()
        self.environment = os.environ.copy()
        for name in tuple(self.environment):
            if name.startswith("FTC_SCOUT_"):
                del self.environment[name]
        # Swift compilation is an expensive external boundary. Invalid signing
        # configuration must fail before the packaging script invokes it.
        self.tools = self.root / "tools"
        self.tools.mkdir()
        swift = self.tools / "swift"
        swift.write_text("#!/bin/sh\necho 'Unexpected Swift invocation' >&2\nexit 72\n")
        swift.chmod(0o755)
        self.environment["PATH"] = f"{self.tools}:{self.environment['PATH']}"

    def run_script(self, name, *arguments):
        source = REPOSITORY / "script" / name
        self.assertTrue(source.is_file(), f"Missing release script: {name}")
        script = self.root / "script" / name
        shutil.copy2(source, script)
        return subprocess.run(
            ["bash", str(script), *arguments],
            env=self.environment,
            text=True,
            capture_output=True,
        )

    def test_app_rejects_missing_public_key_before_building(self):
        result = self.run_script("package_app.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Sparkle public key", result.stderr)
        self.assertNotIn("Unexpected Swift invocation", result.stderr)
        self.assertFalse((self.root / "dist").exists())

    def test_app_rejects_malformed_public_key_before_building(self):
        for value in ("not-a-key", "YWJj", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="):
            with self.subTest(value=value):
                self.environment["FTC_SCOUT_SPARKLE_PUBLIC_KEY"] = value
                result = self.run_script("package_app.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("32-byte Ed25519 public key", result.stderr)
                self.assertNotIn("Unexpected Swift invocation", result.stderr)

    def test_app_reads_valid_public_key_from_config_before_building(self):
        config = self.root / "config"
        config.mkdir()
        (config / "sparkle-public-key.txt").write_text(PUBLIC_KEY + "\n")
        result = self.run_script("package_app.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not compile", result.stderr)
        self.assertIn("Unexpected Swift invocation", (self.root / ".build/swift-build.log").read_text())

    def test_release_rejects_loopback_feeds(self):
        self.environment["FTC_SCOUT_SPARKLE_PUBLIC_KEY"] = PUBLIC_KEY
        for feed in ("http://127.0.0.1:8765/appcast.xml", "https://localhost/appcast.xml"):
            with self.subTest(feed=feed):
                self.environment["FTC_SCOUT_UPDATE_FEED_URL"] = feed
                result = self.run_script("package_app.sh", "release")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("HTTPS", result.stderr)
                self.assertFalse((self.root / ".build").exists())

    def test_debug_accepts_explicit_local_http_feed(self):
        self.environment["FTC_SCOUT_SPARKLE_PUBLIC_KEY"] = PUBLIC_KEY
        self.environment["FTC_SCOUT_UPDATE_FEED_URL"] = "http://127.0.0.1:8765/appcast.xml"
        result = self.run_script("package_app.sh", "debug")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not compile", result.stderr)
        self.assertIn("Unexpected Swift invocation", (self.root / ".build/swift-build.log").read_text())

    def test_update_requires_an_existing_finalized_app(self):
        result = self.run_script("package_update.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("finalized app", result.stderr)
        self.assertFalse((self.root / "dist").exists())


if __name__ == "__main__":
    unittest.main()
