#!/usr/bin/env python3
# XIOM PULSE -- input schema validation matrix (R-14).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# This probe exercises the product route POST /api/session/login
# (schema_string("user", required, 1, 64)):
#
#   * missing, wrong type (number/bool/null/nested object/array) -> 400
#   * empty and 65-byte strings -> 400 min/max
#   * exact 64-byte boundary -> 200
#   * unknown extra fields of every JSON type (number/bool/object/array)
#     -> 200: the documented extra-field policy accepts unknown keys
#   * malformed JSON and a top-level array -> 400
#   * UTF-8 length: the login route uses the backward-compatible BYTE policy,
#     so 32 two-byte chars (64 bytes) pass and 33 (66 bytes) trip the cap.
#
# The schema module also supports string enums (schema_enum) and an opt-in
# UTF-8 CODEPOINT length policy (schema_string_utf8/schema_string_units),
# plus number/bool/object/array rule kinds. Those are module capabilities;
# the product routes here still validate a string field only, so the probe
# records the route coverage as INFO rather than silently skipping it.
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
        reporter.fail(name, "400 invalid_request but message lacks %r: %r"
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
        reporter.fail(name, "200 but no sid in body=%r" % (raw[:160],))
        return
    reporter.ok(name, "200 with sid")


def require_extra_allowed(server, reporter, name, body, kind):
    """Unknown fields are accepted by the documented extra-field policy."""
    status, parsed, raw = post_json(server, body)
    if status == 200:
        reporter.ok(name, "%s extra field accepted (policy: unknown fields "
                    "allowed)" % kind)
        return
    if status == 400:
        code, message = error_fields(parsed)
        if code == "invalid_request" and (
                "extra" in message.lower() or "unknown" in message.lower()):
            reporter.ok(name, "strict policy rejected %s extra field: %s"
                        % (kind, message[:100]))
            return
        reporter.fail(name, "400 with unexpected code=%r message=%r"
                      % (code, message[:100]))
        return
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
        require_ok(server, reporter, "64-byte boundary", {"user": "a" * 64})

        require_error(server, reporter, "missing user", {},
                      "missing required field 'user'")
        require_error(server, reporter, "number value for string", {"user": 123},
                      "must be a string")
        require_error(server, reporter, "bool value for string", {"user": True},
                      "must be a string")
        require_error(server, reporter, "null value for string", {"user": None},
                      "must be a string")
        require_error(server, reporter, "object value for string",
                      {"user": {"nested": 1}}, "must be a string")
        require_error(server, reporter, "array value for string",
                      {"user": [1, 2]}, "must be a string")
        require_error(server, reporter, "empty string", {"user": ""},
                      "at least 1")
        require_error(server, reporter, "65-byte overflow", {"user": "a" * 65},
                      "at most 64")
        require_error(server, reporter, "malformed JSON", "{",
                      "not valid JSON")
        require_error(server, reporter, "top-level array", "[]",
                      "must be a JSON object")

        # Extra-field policy: unknown keys of every JSON type are allowed.
        require_extra_allowed(server, reporter, "extra number field",
                              {"user": "alice", "extra": 1}, "number")
        require_extra_allowed(server, reporter, "extra bool field",
                              {"user": "alice", "extra": True}, "bool")
        require_extra_allowed(server, reporter, "extra object field",
                              {"user": "alice", "extra": {"a": 1}}, "object")
        require_extra_allowed(server, reporter, "extra array field",
                              {"user": "alice", "extra": [1, 2]}, "array")

        # The login route keeps the backward-compatible BYTE policy:
        # 32 x U+00E9 = 32 codepoints but exactly 64 UTF-8 bytes -> 200.
        require_ok(server, reporter, "unicode 64-byte boundary",
                   {"user": "\u00e9" * 32})
        # 33 x U+00E9 = 33 codepoints but 66 bytes -> 400 max.
        require_error(server, reporter, "unicode 65+ byte overflow",
                      {"user": "\u00e9" * 33}, "at most 64")

        reporter.note("UTF-8 codepoint length policy",
                      "schema_string_utf8/schema_string_units counts "
                      "codepoints; login/token keep the default byte policy")
        reporter.note("enum rule",
                      "schema_enum validates string membership (code=enum); "
                      "no product route wires an enum yet")
        reporter.note("number/bool/object/array rule kinds",
                      "schema_number/schema_bool/schema_object/schema_array "
                      "are implemented; the probe exercises those JSON value "
                      "types as wrong-type/extra fields, but no product route "
                      "applies those rule kinds")
    finally:
        server.stop()

    reporter.summary()
    print("schema-matrix-probe: server log %s" % server.log_path)
    return reporter.rc(args.strict)


if __name__ == "__main__":
    sys.exit(lib.main_guard(lambda: main()))
