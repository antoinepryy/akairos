"""Offline tests of the scripts: python3 -m unittest discover -s tests

- check-leftovers.py against simulated OVH answers (no network);
- wait-app-gone.sh (destroy guard) with a fake kubectl, run the way terraform
  runs it (bash -c <content>);
- new-client.sh from a fresh clone of the committed HEAD, so a file that git
  ignores cannot go unnoticed.
"""
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load_check_leftovers():
    spec = importlib.util.spec_from_file_location("check_leftovers", ROOT / "scripts/check-leftovers.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def read(self):
        return self.body


class CheckLeftovers(unittest.TestCase):
    def run_with(self, answer):
        """answer(path) -> bytes body of GET path (token request answered apart)."""
        mod = load_check_leftovers()

        def urlopen(req, data=None, timeout=None):
            self.assertIsNotNone(timeout, "every request needs a timeout")
            if data is not None:
                return FakeResponse(json.dumps({"access_token": "t"}).encode())
            return FakeResponse(answer(req.full_url[len(mod.API):]))

        env = {"OVH_CLIENT_ID": "id", "OVH_CLIENT_SECRET": "secret"}
        with mock.patch.dict(os.environ, env), mock.patch.object(mod.urllib.request, "urlopen", urlopen), \
                mock.patch.object(mod, "CHECK_BUCKET", ""), redirect_stdout(io.StringIO()) as out:
            with self.assertRaises(SystemExit) as code:
                mod.main()
                raise SystemExit(0)
        return code.exception.code, out.getvalue()

    def test_clean_project(self):
        code, out = self.run_with(lambda path: b"[]")
        self.assertEqual(code, 0)
        self.assertIn("nothing left", out)

    def test_leftover_reported(self):
        def answer(path):
            if path.endswith("/loadbalancing/loadbalancer"):
                return json.dumps([{"name": "kube_service_x_web_web", "id": "lb1"}]).encode()
            return b"[]"
        code, out = self.run_with(answer)
        self.assertEqual(code, 1)
        self.assertIn("kube_service_x_web_web", out)

    def test_empty_body_is_incomplete(self):
        code, out = self.run_with(lambda path: b"")
        self.assertEqual(code, 2)
        self.assertNotIn("nothing left", out)

    def test_null_answer_is_incomplete(self):
        code, out = self.run_with(lambda path: b"null")
        self.assertEqual(code, 2)

    def test_wrong_type_is_incomplete(self):
        code, out = self.run_with(lambda path: b'{"message": "oops"}')
        self.assertEqual(code, 2)


class DestroyGuard(unittest.TestCase):
    SCRIPT = (ROOT / "modules/k8s-stack/scripts/wait-app-gone.sh").read_text()

    def run_guard(self, mode, **extra):
        with tempfile.TemporaryDirectory() as bin_dir:
            kubectl = Path(bin_dir) / "kubectl"
            kubectl.write_text(
                "#!/bin/sh\n"
                'case "$FAKE_MODE" in\n'
                '  present) echo service/web ;;\n'
                '  finalizing) case "$*" in *applications*) echo application/web ;; esac ;;\n'
                '  absent) ;;\n'
                '  error) echo "Unable to connect" >&2; exit 1 ;;\n'
                "esac\n")
            kubectl.chmod(0o755)
            env = {"PATH": f"{bin_dir}:/usr/bin:/bin", "FAKE_MODE": mode, "KUBECONFIG_CONTENT": "x",
                   "WAIT_TRIES": "2", "WAIT_SLEEP": "0", "APP_NAMESPACE": "web", **extra}
            # Run from an unrelated directory, as a destroy from another checkout would.
            return subprocess.run(["bash", "-c", self.SCRIPT], env=env, cwd=bin_dir,
                                  capture_output=True, text=True, timeout=30)

    def test_gone(self):
        self.assertEqual(self.run_guard("absent").returncode, 0)

    def test_still_present_blocks_destroy(self):
        r = self.run_guard("present")
        self.assertEqual(r.returncode, 1)
        self.assertIn("still present", r.stderr)

    def test_application_still_finalizing_blocks_destroy(self):
        r = self.run_guard("finalizing")
        self.assertEqual(r.returncode, 1)
        self.assertIn("application/web", r.stderr)

    def test_kubectl_error_never_counts_as_gone(self):
        r = self.run_guard("error")
        self.assertEqual(r.returncode, 1)
        self.assertIn("kubectl error", r.stderr)

    def test_disabled(self):
        self.assertEqual(self.run_guard("present", GUARD_ENABLED="false").returncode, 0)


class NewClient(unittest.TestCase):
    PROJECT = "0123456789abcdef0123456789abcdef"

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.clone = Path(cls.tmp.name) / "akairos"
        subprocess.run(["git", "clone", "-q", str(ROOT), str(cls.clone)], check=True)
        subprocess.run(["git", "-C", str(cls.clone), "tag", "v0.0.0-test"], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def generate(self, dest, *args):
        env = {**os.environ, "AKAIROS_REF": "v0.0.0-test"}
        return subprocess.run([str(self.clone / "scripts/new-client.sh"), str(dest), *args],
                              env=env, capture_output=True, text=True, timeout=60)

    def test_generates_complete_repository(self):
        dest = Path(self.tmp.name) / "acme"
        r = self.generate(dest, r"D&A | Test \ Corp", "acme", self.PROJECT, "SBG5", "acme-corp/platform")
        self.assertEqual(r.returncode, 0, r.stderr)
        for name in ["client.tfvars", "main.tf", "variables.tf", "backend.hcl", "env.sh",
                     "scripts/kubeconfig.sh", "apps/web/Chart.yaml", ".gitignore"]:
            self.assertTrue((dest / name).is_file(), f"{name} missing")
        self.assertTrue(os.access(dest / "scripts/kubeconfig.sh", os.X_OK))
        tfvars = (dest / "client.tfvars").read_text()
        self.assertIn(f'service_name = "{self.PROJECT}"', tfvars)
        self.assertIn('kube_version  = "1.35"', tfvars)
        self.assertIn("git@github.com:acme-corp/platform.git", tfvars)
        self.assertIn(r"D&A | Test \ Corp", tfvars)
        self.assertIn("?ref=v0.0.0-test", (dest / "main.tf").read_text())
        self.assertIn("OVH_ACME_CLIENT_ID", (dest / "env.sh").read_text())
        self.assertIn("s3.sbg.io.cloud.ovh.net", (dest / "backend.hcl").read_text())
        for f in dest.rglob("*"):
            if f.is_file() and ".git" not in f.parts:
                self.assertNotRegex(f.read_text(), r"__[A-Z_]+__", f"placeholder left in {f}")

    def test_env_exports_only_this_client(self):
        dest = Path(self.tmp.name) / "envtest"
        self.assertEqual(self.generate(dest, "ACME", "acme", self.PROJECT, "SBG5", "o/r").returncode, 0)
        secrets = Path(self.tmp.name) / "secrets.env"
        secrets.write_text("OVH_ACME_CLIENT_ID=cid\nOVH_ACME_CLIENT_SECRET=csec\n"
                           "OVH_ACME_S3_ACCESS_KEY=ak\nOVH_ACME_S3_SECRET_KEY=sk\nOTHER_CLIENT_TOKEN=nope\n")
        bin_dir = Path(self.tmp.name) / "bin"
        bin_dir.mkdir(exist_ok=True)
        (bin_dir / "curl").write_text("#!/bin/sh\nexit 1\n")  # offline: no IP detection
        (bin_dir / "curl").chmod(0o755)
        script = ('. ./env.sh 2>/dev/null; echo "$OVH_CLIENT_ID/$AWS_SECRET_ACCESS_KEY/$TF_VAR_prefix";'
                  ' echo "other=${OTHER_CLIENT_TOKEN:-}"; env | grep -c OTHER_CLIENT || true')
        r = subprocess.run(["bash", "-c", script], cwd=dest, capture_output=True, text=True, timeout=30,
                           env={"PATH": f"{bin_dir}:/usr/bin:/bin", "HOME": self.tmp.name, "SECRETS": str(secrets)})
        self.assertEqual(r.stdout.split(), ["cid/sk/acme", "other=", "0"])

    def test_rejects_bad_inputs(self):
        cases = [
            ("ACME", "Acme", self.PROJECT, "SBG5", "o/r"),      # prefix in capitals
            ("ACME", "acme", "xyz", "SBG5", "o/r"),             # project id
            ("ACME", "acme", self.PROJECT, "sbg5", "o/r"),      # region in lowercase
            ("ACME", "acme", self.PROJECT, "SBG5", "noslash"),  # repository
            ('AC"ME', "acme", self.PROJECT, "SBG5", "o/r"),     # quote in the name
        ]
        for i, args in enumerate(cases):
            dest = Path(self.tmp.name) / f"bad{i}"
            r = self.generate(dest, *args)
            self.assertEqual(r.returncode, 2, args)
            self.assertFalse(dest.exists(), args)


if __name__ == "__main__":
    sys.exit(unittest.main())
