#!/usr/bin/env python3
# XIOM PULSE -- bidirectional OpenAPI drift probe (W-14, reverse of
# `openapi --check`).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# `openapi --check` walks router.route_defs() and reports routes missing
# from resources/openapi.json (routes -> document only). This probe adds the
# reverse direction:
#
#   * every operation in resources/openapi.json must be in the route table
#     (or be a known served special-case)
#   * stream-registry routes (GET /api/sse, GET /api/ws) must be accounted
#     for; today they are not in the document
#   * the route table must not contain duplicate operations
#   * the CLI `openapi --check` must still pass
#
# Served surface accounted for on both directions (fixed 2026-11-07):
#   - GET /assets/{path} is in the document but not in route_defs; it is
#     served by the dispatch_one /assets/ special-case (src/server.xi:272)
#     and is registered in src/openapi.xi openapi_extra_routes().
#   - GET /api/sse and GET /api/ws are stream-registry routes, printed by
#     `routes`, registered in src/openapi.xi openapi_extra_routes(), and
#     present in the OpenAPI paths object.
#
# Usage:
#   python scripts/openapi_drift_probe.py --exe out/pulse_gap_18700.exe \
#       [--doc resources/openapi.json] [--strict]
#
# Exit: 0 = no FAIL (known GAPs allowed unless --strict), 1 = FAIL/strict
#       GAP, 2 = setup error.

import argparse
import json
import os
import re
import sys
import tempfile

import gap_probe_lib as lib

METHODS = {"get", "post", "put", "delete", "patch", "head", "options", "trace"}
ROUTE_RE = re.compile(
    r"^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|TRACE)\s+(\S+?)"
    r"(?:\s+\((sse|ws)\))?$")
PARAM_RE = re.compile(r":([^/]+)")


def template(pattern):
    return PARAM_RE.sub(r"{\1}", pattern)


def parse_routes(text):
    """Split the `routes` CLI block into router routes and stream routes."""
    router = []
    streams = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        match = ROUTE_RE.match(line)
        if not match:
            continue
        method, path, kind = match.group(1), match.group(2), match.group(3)
        if kind:
            streams.append((method, path))
        else:
            router.append((method, path))
    return router, streams


def load_doc(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def doc_operations(doc):
    ops = set()
    duplicates = []
    paths = doc.get("paths")
    if not isinstance(paths, dict):
        return ops, duplicates, "paths object missing"
    for path, item in paths.items():
        if not isinstance(item, dict):
            continue
        seen_lower = {}
        for key in item:
            lower = key.lower()
            if lower not in METHODS:
                continue
            if lower in seen_lower:
                duplicates.append((path, seen_lower[lower], key))
            seen_lower[lower] = key
            ops.add((key.upper(), path))
    return ops, duplicates, ""


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="PULSE bidirectional OpenAPI drift probe (W-14)")
    parser.add_argument("--exe", default="out/pulse_gap_18700.exe",
                        help="server binary (default: %(default)s)")
    parser.add_argument("--doc", default="resources/openapi.json",
                        help="OpenAPI file (default: %(default)s)")
    parser.add_argument("--strict", action="store_true",
                        help="exit 1 when the known GAPs are still present")
    args = parser.parse_args(argv)

    exe = lib.require_exe(args.exe)
    if not exe:
        return 2
    doc_path = args.doc
    if not os.path.isabs(doc_path):
        doc_path = os.path.join(lib.repo_root(), doc_path)
    if not os.path.exists(doc_path):
        print("[FAIL] OpenAPI document not found: %s" % doc_path)
        return 2

    reporter = lib.Reporter("openapi-drift-probe")
    print("openapi-drift-probe: %s" % exe)
    print("openapi-drift-probe: doc %s" % doc_path)

    # Route table is the CLI view of router.route_defs() + the stream registry.
    routes_rc, routes_out = lib.run_cli(exe, ["routes"])
    if routes_rc != 0:
        reporter.fail("routes CLI", "rc=%d output=%r"
                      % (routes_rc, routes_out[:300]))
        reporter.summary()
        return reporter.rc(args.strict)
    router_routes, stream_routes = parse_routes(routes_out)
    router_ops = {(method, template(path)) for method, path in router_routes}
    stream_ops = {(method, template(path)) for method, path in stream_routes}
    reporter.note("route table",
                  "router=%d stream=%d" % (len(router_ops), len(stream_ops)))

    duplicate_routes = []
    seen = set()
    for method, path in router_routes:
        op = (method, template(path))
        if op in seen:
            duplicate_routes.append(op)
        seen.add(op)
    if duplicate_routes:
        reporter.fail("duplicate route-table entries",
                      ", ".join("%s %s" % op for op in sorted(duplicate_routes)))
    else:
        reporter.ok("duplicate route-table entries", "none")

    # One-way CLI check (must remain green).
    check_rc, check_out = lib.run_cli(exe, ["openapi", "--check"])
    if check_rc == 0:
        reporter.ok("openapi --check", check_out.strip()[:160])
    else:
        reporter.fail("openapi --check",
                      "rc=%d output=%r" % (check_rc, check_out[:400]))

    # Document inventory.
    try:
        doc = load_doc(doc_path)
    except (OSError, ValueError) as exc:
        reporter.fail("document parse", repr(exc))
        reporter.summary()
        return reporter.rc(args.strict)
    if not doc.get("openapi"):
        reporter.fail("document openapi field", "missing version")
    else:
        reporter.ok("document openapi field", doc["openapi"])

    # `--check` failure path: inject drift into a temp copy (never the repo
    # document) and prove the one-way gate exits non-zero with the route name.
    broken = json.loads(json.dumps(doc))
    broken_paths = broken.get("paths") if isinstance(broken, dict) else None
    if isinstance(broken_paths, dict) and "/health" in broken_paths:
        del broken_paths["/health"]
        tmp_path = ""
        try:
            fd, tmp_path = tempfile.mkstemp(
                prefix="pulse-openapi-broken-", suffix=".json")
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(broken, fh)
            inj_rc, inj_out = lib.run_cli(
                exe, ["openapi", "--check"],
                env_overrides={"PULSE_OPENAPI_PATH": tmp_path})
            if inj_rc != 0 and "missing GET /health" in inj_out:
                reporter.ok("openapi --check detects injected drift",
                            "rc=%d" % inj_rc)
            else:
                reporter.fail("openapi --check detects injected drift",
                              "rc=%d output=%r" % (inj_rc, inj_out[:300]))
        finally:
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
    else:
        reporter.gap("openapi --check detects injected drift",
                     "/health not present in the document")

    doc_ops, doc_duplicates, doc_error = doc_operations(doc)
    if doc_error:
        reporter.fail("document paths", doc_error)
    if doc_duplicates:
        reporter.fail("duplicate document operations",
                      ", ".join("%s %s/%s" % d for d in doc_duplicates))
    else:
        reporter.ok("duplicate document operations", "none")
    reporter.note("document operations", str(len(doc_ops)))

    # Direction 1: route table -> document.
    missing_doc = sorted(router_ops - doc_ops)
    if missing_doc:
        reporter.fail("router route missing from document",
                      ", ".join("%s %s" % op for op in missing_doc))
    else:
        reporter.ok("router route missing from document", "none")

    # Direction 2: document -> route table / stream registry / served extras.
    # Keep this in sync with openapi.openapi_extra_routes() in src/openapi.xi:
    # those routes are served without a route_defs() entry.
    served_extra = {("GET", "/assets/{path}")}
    doc_only = doc_ops - router_ops - stream_ops
    unknown_doc_only = doc_only - served_extra
    if unknown_doc_only:
        reporter.fail("document operation missing from route table",
                      ", ".join("%s %s" % op for op in
                                sorted(unknown_doc_only)))
    else:
        reporter.ok("document operation missing from route table",
                    "none beyond served extras")

    missing_extra = sorted(served_extra - doc_ops)
    if missing_extra:
        reporter.fail("served special-case missing from document",
                      ", ".join("%s %s" % op for op in missing_extra))
    else:
        reporter.ok("served special-case documented",
                    ", ".join("%s %s" % op
                              for op in sorted(served_extra & doc_ops)))

    # Stream-registry routes are part of the document (fixed 2026-11-07).
    stream_missing = sorted(stream_ops - doc_ops)
    if stream_missing:
        reporter.fail("stream route missing from document",
                      ", ".join("%s %s" % op for op in stream_missing))
    else:
        reporter.ok("stream route missing from document", "none")

    # The /v1 alias is a servers entry, not duplicate paths; record it.
    v1_servers = [
        entry.get("url", "") for entry in doc.get("servers", [])
        if isinstance(entry, dict) and "/v1" in entry.get("url", "")
    ]
    if v1_servers:
        reporter.note("/v1 alias", ", ".join(v1_servers))
    else:
        reporter.gap("/v1 alias", "no /v1 server entry in the document")

    reporter.summary()
    return reporter.rc(args.strict)


if __name__ == "__main__":
    sys.exit(lib.main_guard(lambda: main()))
