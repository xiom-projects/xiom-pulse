#!/usr/bin/env python3
# ============================================================================
# XIOM PULSE -- app scaffold smoke (cross-platform).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Creates a temporary app from scaffolds/api, builds it with the pinned
# toolchain, starts it on a local port, and checks /health, /api/hello, /,
# the POST echo and the JSON 404. Cleans up. Exit 0 = GREEN, 1 = failure.
#
# Usage: python scripts/scaffold_smoke.py
# ============================================================================
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "pulse-scaffold-app"
PORT = 18099
EXE = ROOT / "out" / ("scaffold_app.exe" if os.name == "nt" else "scaffold_app")


def http(method, path, data=None, timeout=3):
    url = "http://127.0.0.1:{}{}".format(PORT, path)
    request = urllib.request.Request(url, data=data, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")


def rm(path):
    try:
        path.unlink()
    except OSError:
        pass


def main():
    work = Path(tempfile.mkdtemp(prefix="pulse-scaffold-"))
    app_dir = work / APP
    proc = None
    failures = 0

    def check(name, ok, detail=""):
        nonlocal failures
        if ok:
            print("[PASS] " + name)
        else:
            print("[FAIL] " + name + (" :: " + detail if detail else ""))
            failures += 1

    try:
        subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "new_app.py"), APP, str(app_dir)],
            check=True,
            cwd=str(ROOT),
        )
        if os.name == "nt":
            build = [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "build.ps1"),
                str(app_dir / "src" / "main.xi"),
                "-Name",
                "scaffold_app",
                "-TimeoutSec",
                "300",
            ]
        else:
            build = [
                "bash",
                str(ROOT / "scripts" / "build.sh"),
                str(app_dir / "src" / "main.xi"),
                "--name",
                "scaffold_app",
                "--timeout-sec",
                "300",
            ]
        built = subprocess.run(build, cwd=str(ROOT), capture_output=True, text=True)
        if built.returncode != 0:
            print(built.stdout)
            print(built.stderr, file=sys.stderr)
            print("scaffold-smoke: build failed")
            return 1
        if not EXE.is_file():
            print("scaffold-smoke: build produced no {}".format(EXE))
            return 1

        env = dict(os.environ)
        env["PULSE_PORT"] = str(PORT)
        env["PULSE_LOG"] = "0"
        proc = subprocess.Popen(
            [str(EXE)],
            cwd=str(ROOT),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        ready = False
        for _ in range(100):
            try:
                status, body = http("GET", "/health", timeout=2)
                if status == 200 and '"status":"ok"' in body:
                    ready = True
                    break
            except Exception:
                pass
            if proc.poll() is not None:
                break
            time.sleep(0.2)
        if not ready:
            output = b""
            if proc.poll() is not None:
                output = proc.stdout.read() if proc.stdout else b""
            print("scaffold-smoke: server did not become ready")
            if output:
                print(output.decode("utf-8", "replace"))
            return 1

        status, body = http("GET", "/health")
        check("health 200", status == 200 and '"status":"ok"' in body, body)

        status, body = http("GET", "/api/hello")
        check("hello 200", status == 200 and "Hello, World!" in body, body)

        status, body = http("GET", "/")
        check("root identity", status == 200 and APP in body, body)

        status, body = http("POST", "/api/echo", data=b"hello-scaffold")
        check("echo 200", status == 200 and body == "hello-scaffold", body)

        status, body = http("GET", "/nope")
        check("404 JSON", status == 404 and '"not_found"' in body, body)

        if failures == 0:
            print("scaffold-smoke: GREEN")
            return 0
        print("scaffold-smoke: RED failures={}".format(failures))
        return 1
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        shutil.rmtree(work, ignore_errors=True)
        rm(EXE)
        rm(Path(str(EXE) + ".ll"))


if __name__ == "__main__":
    sys.exit(main())
