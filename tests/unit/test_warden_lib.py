"""warden_lib.load_env — every cron job reads its configuration through it, with the panel's live
settings.local overlaid on top."""
import os, sys, tempfile, unittest
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))
os.environ.setdefault("WARDEN_ENV", "/nonexistent/app.env")
import warden_lib


class LoadEnv(unittest.TestCase):
    def test_quoting_comments_and_the_local_overlay(self):
        root = tempfile.mkdtemp(prefix="mc-env-"); os.makedirs(os.path.join(root, "controllarr"))
        p = os.path.join(root, "app.env")
        with open(p, "w") as f: f.write(f"# comment\nCONFIG_DIR={root}\nQBIT_PASS='p a$s'\nEMPTY=\nPLAIN=x=y\n  INDENTED=1\nNOEQUALS\n")
        with open(os.path.join(root, "controllarr", "settings.local"), "w") as f: f.write("MIN_SEEDERS=9\nPLAIN=override\n")
        d = warden_lib.load_env(p)
        self.assertEqual(d["QBIT_PASS"], "p a$s"); self.assertEqual(d["EMPTY"], ""); self.assertEqual(d["PLAIN"], "override")
        self.assertEqual(d["MIN_SEEDERS"], "9"); self.assertEqual(d["INDENTED"], "1"); self.assertNotIn("NOEQUALS", d)
        self.assertEqual(warden_lib.load_env("/nonexistent"), {})
    def test_quiet_hours_wrap_midnight(self):
        with mock.patch.dict(warden_lib.E, {"NOTIFY_QUIET_START": "22", "NOTIFY_QUIET_END": "7"}):
            for h, want in ((23, True), (3, True), (7, False), (12, False)):
                with mock.patch("warden_lib.time.localtime", return_value=mock.Mock(tm_hour=h)): self.assertEqual(warden_lib._quiet_now(), want, h)
        with mock.patch.dict(warden_lib.E, {"NOTIFY_QUIET_START": "0", "NOTIFY_QUIET_END": "9"}):
            with mock.patch("warden_lib.time.localtime", return_value=mock.Mock(tm_hour=8)): self.assertTrue(warden_lib._quiet_now())
            with mock.patch("warden_lib.time.localtime", return_value=mock.Mock(tm_hour=9)): self.assertFalse(warden_lib._quiet_now())
    def test_apikey_falls_back_to_env(self):
        with mock.patch.dict(warden_lib.E, {"RADARR_APIKEY": "from-env"}): self.assertEqual(warden_lib.apikey("radarr"), "from-env")


if __name__ == "__main__":
    unittest.main()
