<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Consumer-verify: xiom.ssl 0.1.0 (PULSE side)

Scope: the packages lane's delivery of the PULSE TLS headline
(`REL-20261015-2211-packages` accepted; eco-v0.1.189, sha256
`ba42cf2b...`, announced at `REL-20261016-1515-packages`). This unit
consumes the INSTALLED registry artifact; the live leg proves a real
TLS 1.3 handshake entirely in-process (memory-BIO pump, no socket)
using the artifact's own fixtures.

## Result

- **Windows live leg: 14/14 GREEN x2** (`ssl-win-live.log`): probe
  `OpenSSL 3.2.4`; server context from the fixture PEMs + key
  consistency; client context with the ALPN list; memory-BIO streams;
  full TLS handshake with **no socket**; TLSv1.3 + equal cipher on both
  ends; app data both directions; ALPN negotiated-read empty (no server
  selector -- documented limitation); clean shutdown (close_notify both
  ways); untrusted self-signed rejected with a typed handshake error and
  `verify_result != 0`.
- **WSL Ubuntu: SKIP leg 4/4 GREEN x2** (`ssl-linux.log`): the loader is
  Windows-soname focused, so the Linux leg verifies the documented SKIP
  contract (typed `SSL_LOAD_ABSENT`) plus the pure checks (ALPN wire
  golden, verify catalog).
- The install checksum matched the published sha256 on both stores.

## How to run

- Install once: `xiom pkg install xiom.ssl@0.1.0`.
- Fixtures: set `SSL_CERT_PATH` / `SSL_KEY_PATH` to the installed
  package's `tests/fixtures/server-{cert,key}.pem`.
- Live leg: prepend `C:\Program Files\Git\mingw64\bin` to `PATH`
  (libssl-3-x64.dll), then from this directory: `xiom --run probe.xi`
  (exit code = failures). Without a loadable libssl the same command
  runs the SKIP leg.
- Wrappers used for this session's evidence:
  `probe-logs/packages-verify/run-win-ssl.ps1` and `run-linux-ssl.sh`.

## Evidence

- `probe-logs/packages-verify/ssl-win-live.log` (`LIVE=1 FAILS=0` x2) /
  `ssl-linux.log` (`LIVE=0` SKIP leg `FAILS=0` x2).
- Bus: result filed to packages (ref `REL-20261016-1515-packages`).
