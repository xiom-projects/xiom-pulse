#!/usr/bin/env python3
# XIOM PULSE -- input schema validation matrix (R-14).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# The audit's R-14 row says schema coverage is string/length only and asks
# for a missing/extra/wrong-type/nested/enum matrix returning the 400
# envelope. This probe exercises the product route POST /api/session/login
# (schema_string("user", required, 1, 64)):
#
#   * missing, wrong type (number/bool/null), nested object, array -> 400
#   * empty and 65-char strings -> 400 min/max
#   * exact 64-char boundary -> 200
#   * unknown extra scalar/object fields -> current 200 (allowed by the
#     schema module's "unknown extra fields are allowed" contract)
#   * malformed JSON and a top-level array -> 400
#   * unicode length uses byte length, not character count -> 200 expected
#     for 33 two-byte chars, current 400
#
# Enum and the number/bool/object/array rule kinds have no product route;
# those are reported as GAPs rather than silently skipped.
#
# Usage:
#   python scripts/schema_matrix_probe.py --exe out/pulse_gap_18700.exe \
#       --port 18722 [--strict]
#
# Exit: 0 = no FAIL (GAPs allowed unless --strict), 1 = FAIL/strict GAP,
#       2 = setup error.

import argparse
import http.client
import json
import sys

import gap_probe_lib as lib


def post_json(server, body, content_type="application/json"):
    if isinstance(body, str):
        payload = body.encode("utf-8")
    else:
        payload = json.dumps(body, separators=(",", ":")).encode("utf-8")
    conn = http.client.HTTPConnection(
        "127.0.0.1", server.port, timeout=5.0)
    try:
        conn.request(
            "POST", "/api/session/login", body=payload,
            headers={"Content-Type": content_type,
                     "Content-Length": str(len(payload))})
        resp = conn.getresponse()
        raw = resp.read()
        status = resp.status
    finally:
        conn.close()
    try:
        parsed = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        parsed = None
    return status, parsed, raw


def error_fields(parsed):
    if not isinstance(parsed, dict):
        return "", ""
    err = parsed.get("error")
    if not isinstance(err, dict):
        return "", ""
    return err.get("code", ""), err.get("message", "")


def require_error(server, reporter, name, body, fragment=""):
    status, parsed, raw = post_json(server, body)
    code, message = error_fields(parsed)
    if status != 400 or code != "invalid_request":
        reporter.fail(name, "expected 400 invalid_request; got status=%s "
                      "code=%r body=%r" % (status, code, raw[:200]))
        return
    if fragment and fragment not in message:
        reporter.gap(name, "400 invalid_request but message lacks %r: %r"
                     % (fragment, message))
        return
    reporter.ok(name, "%s: %s" % (code, message[:100]))


def require_ok(server, reporter, name, body):
    status, parsed, raw = post_json(server, body)
    if status != 200:
        code, message = error_fields(parsed)
        reporter.fail(name, "expected 200; got status=%s code=%r message=%r"
                      % (status, code, message))
        return
    if not isinstance(parsed, dict) or not parsed.get("sid"):
        reporter.gap(name, "200 but no sid in body=%r" % (raw[:160],))
        return
    reporter.ok(name, "200 with sid")


def check_extra(server, reporter, name, body):
    status, parsed, raw = post_json(server, body)
    if status == 200:
        reporter.gap(name, "extra field accepted (200); schema allows "
                     "unknown fields by design")
    elif status == 400:
        code, message = error_fields(parsed)
        if code == "invalid_request":
            reporter.ok(name, "extra field rejected: %s" % message[:100])
        else:
            reporter.fail(name, "400 with unexpected code=%r" % (code,))
    else:
        reporter.fail(name, "expected 200 or 400; got status=%s body=%r"
                      % (status, raw[:160]))


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="PULSE input schema validation matrix (R-14)")
    parser.add_argument("--exe", default="out/pulse_gap_18700.exe",
                        help="server binary (default: %(default)s)")
    parser.add_argument("--port", type=int, default=18722,
                        help="private port 18700+ (default: %(default)s)")
    parser.add_argument("--strict", action="store_true",
                        help="exit 1 when any known GAP is observed")
    args = parser.parse_args(argv)

    exe = lib.require_exe(args.exe)
    if not exe:
        return 2

    reporter = lib.Reporter("schema-matrix-probe")
    server = lib.Server(exe, args.port, "schema-gap", read_timeout_ms=2000)
    try:
        server.start()
    except RuntimeError as exc:
        print("[FAIL] %s" % exc)
        return 2

    print("schema-matrix-probe: %s port=%d" % (exe, args.port))
    try:
        require_ok(server, reporter, "valid user", {"user": "alice"})
        require_ok(server, reporter, "64-char boundary", {"user": "a" * 64})

        require_error(server, reporter, "missing user", {},
                      "missing required field 'user'")
        require_error(server, reporter, "wrong type number", {"user": 123},
                      "must be a string")
        require_error(server, reporter, "wrong type bool", {"user": True},
                      "must be a string")
        require_error(server, reporter, "wrong type null", {"user": None},
                      "must be a string")
        require_error(server, reporter, "nested object for string",
                      {"user": {"nested": 1}}, "must be a string")
        require_error(server, reporter, "array for string",
                      {"user": [1, 2]}, "must be a string")
        require_error(server, reporter, "empty string", {"user": ""},
                      "at least 1")
        require_error(server, reporter, "65-char overflow", {"user": "a" * 65},
                      "at most 64")
        require_error(server, reporter, "malformed JSON", "{",
                      "not valid JSON")
        require_error(server, reporter, "top-level array", "[]",
                      "must be a JSON object")

        check_extra(server, reporter, "extra scalar field",
                    {"user": "alice", "extra": 1})
        check_extra(server, reporter, "extra nested field",
                    {"user": "alice", "extra": {"a": 1}})

        # Length is measured in bytes today: 33 x U+00E9 is 33 characters
        # but 66 UTF-8 bytes, so it trips the 64-byte cap.
        status, parsed, raw = post_json(
            server, {"user": "\u00e9" * 33})
        if status == 200:
            reporter.ok("unicode length boundary", "33 two-byte chars accepted")
        elif status == 400:
            code, message = error_fields(parsed)
            reporter.gap("unicode length boundary",
                         "33 chars (66 bytes) rejected: %s" % message[:100])
        else:
            reporter.fail("unicode length boundary",
                          "got status=%s body=%r" % (status, raw[:160]))

        reporter.gap("enum rule",
                     "no enum rule kind or product route; R-14 enum case "
                     "cannot return a 400 envelope today")
        reporter.gap("number/bool/object/array rules",
                     "schema_number/schema_bool/schema_object/schema_array "
                     "exist but no product route exercises them")
    finally:
        server.stop()

    reporter.summary()
    print("schema-matrix-probe: server log %s" % server.log_path)
    return reporter.rc(args.strict)


if __name__ == "__main__":
    sys.exit(lib.main_guard(lambda: main()))
