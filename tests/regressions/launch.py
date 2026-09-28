"""Run one suite behind the Linux namespace gate with closed inherited FDs."""

import os
import platform
import selectors
import signal
import subprocess
import sys
import tempfile
import time

if len(sys.argv) != 2 or sys.argv[1] not in {
    "statusline",
    "sqlite",
    "first_lint",
    "first_lint_cli",
    "gutter_saveas",
    "gutter_superseded",
    "vc_failure",
    "gutter_empty",
    "pins",
}:
    raise SystemExit(
        "usage: launch.py {statusline|sqlite|first_lint|first_lint_cli|gutter_saveas|gutter_superseded|vc_failure|gutter_empty|pins}"
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
if sys.argv[1] in {"gutter_saveas", "gutter_superseded", "vc_failure", "gutter_empty"}:
    env["TEST_GIT"] = os.environ["TEST_GIT"]
env["TMPDIR"] = os.environ.get("TMPDIR", "/tmp")
required = keys + (("TEST_SQLITE",) if sys.argv[1] == "sqlite" else ())
if sys.argv[1] in {"gutter_saveas", "gutter_superseded", "vc_failure", "gutter_empty"}:
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
owner = {"proc": None, "pending": None}


def cancel(signum, _frame):
    if owner["proc"] is None:
        owner["pending"] = signum
    else:
        raise SystemExit(128 + signum)


cancel_signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
previous_handlers = {sig: signal.signal(sig, cancel) for sig in cancel_signals}
try:
    with tempfile.TemporaryDirectory(
        prefix="poincare-regress-", dir=env["TMPDIR"]
    ) as temp_root:
        env["TMPDIR"] = temp_root
        proc = None
        completed = False
        try:
            if owner["pending"] is not None:
                raise SystemExit(128 + owner["pending"])
            proc = subprocess.Popen(
                cmd,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                close_fds=True,
                start_new_session=True,
            )
            owner["proc"] = proc
            if owner["pending"] is not None:
                raise SystemExit(128 + owner["pending"])
            with selectors.DefaultSelector() as selector:
                selector.register(proc.stdout, selectors.EVENT_READ, sys.stdout.buffer)
                selector.register(proc.stderr, selectors.EVENT_READ, sys.stderr.buffer)
                deadline = time.monotonic() + 120
                while selector.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(cmd, 120)
                    for key, _ in selector.select(remaining):
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        if chunk:
                            key.data.write(chunk)
                            key.data.flush()
                        else:
                            selector.unregister(key.fileobj)
                            key.fileobj.close()
                code = proc.wait(timeout=max(0, deadline - time.monotonic()))
            completed = True
            raise SystemExit(code)
        except subprocess.TimeoutExpired:
            raise SystemExit("isolated regression exceeded 120 seconds")
        finally:
            for sig in cancel_signals:
                signal.signal(sig, signal.SIG_IGN)
            if proc is not None:
                if not completed:
                    try:
                        os.killpg(proc.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        try:
                            os.killpg(proc.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        proc.wait()
                proc.stdout.close()
                proc.stderr.close()
finally:
    for sig, handler in previous_handlers.items():
        signal.signal(sig, handler)
