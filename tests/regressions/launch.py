"""Run one suite behind the Linux namespace gate with closed inherited FDs."""

import os
import platform
import signal
import subprocess
import sys
import tempfile

if len(sys.argv) != 2 or sys.argv[1] not in {
    "statusline",
    "sqlite",
    "first_lint",
    "first_lint_cli",
    "gutter_saveas",
    "gutter_superseded",
    "vc_failure",
}:
    raise SystemExit(
        "usage: launch.py {statusline|sqlite|first_lint|first_lint_cli|gutter_saveas|gutter_superseded|vc_failure}"
    )
if platform.system() != "Linux":
    raise SystemExit("focused regressions require Linux user/mount/network namespaces")

keys = (
    "MINI_TEST_RTP",
    "POINCARE_PACKPATH",
    "TEST_NVIM",
    "TEST_BASH",
    "TEST_CORE",
    "TEST_UTIL",
    "TEST_IP",
    "TEST_NIX",
    "TEST_PYTHON",
    "TEST_SELENE",
)
env = {key: os.environ[key] for key in keys}
if sys.argv[1] == "sqlite":
    env["TEST_SQLITE"] = os.environ["TEST_SQLITE"]
if sys.argv[1] in {"gutter_saveas", "gutter_superseded", "vc_failure"}:
    env["TEST_GIT"] = os.environ["TEST_GIT"]
env["TMPDIR"] = os.environ.get("TMPDIR", "/tmp")
required = keys + (("TEST_SQLITE",) if sys.argv[1] == "sqlite" else ())
if sys.argv[1] in {"gutter_saveas", "gutter_superseded", "vc_failure"}:
    required += ("TEST_GIT",)
for key in required:
    if not os.path.isdir(env[key]):
        raise SystemExit(f"missing regression prerequisite {key}: {env[key]}")
env["PATH"] = ":".join(
    env[key] + "/bin"
    for key in (
        "TEST_CORE",
        "TEST_UTIL",
        "TEST_IP",
        "TEST_NIX",
        "TEST_PYTHON",
        "TEST_BASH",
    )
)
cmd = [
    env["TEST_UTIL"] + "/bin/unshare",
    "--user",
    "--map-root-user",
    "--mount",
    "--pid",
    "--net",
    "--ipc",
    "--uts",
    "--fork",
    "--kill-child",
    env["TEST_BASH"] + "/bin/bash",
    "tests/regressions/isolated.sh",
    sys.argv[1],
]
with tempfile.TemporaryDirectory(
    prefix="poincare-regress-", dir=env["TMPDIR"]
) as temp_root:
    env["TMPDIR"] = temp_root
    proc = subprocess.Popen(cmd, env=env, close_fds=True, start_new_session=True)
    try:
        raise SystemExit(proc.wait(timeout=120))
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        raise SystemExit("isolated regression exceeded 120 seconds")
