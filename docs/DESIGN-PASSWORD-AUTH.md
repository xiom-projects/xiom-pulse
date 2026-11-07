<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: password authentication (audit S-08)

Status: **DESIGN ONLY (2026-11-07)**. Nothing in this document is
implemented. It creates no source, test, CI, or configuration change and
does not close S-08. `docs/PARITY-MATRIX.md:88` and
`docs/FEATURE-TESTS.md:167` remain correct: PULSE login is user-only and
there is no password field, credential store, or hash.

Scope: the cookie-session login (`POST /api/session/login`), the sibling
JWT mint (`POST /api/token`), session/CSRF integration, the credential
store, login throttling/lockout, timing behavior, error responses,
migration, and the test/release gates required to claim S-08 closed.

## 1. Current behavior (verified against the tree)

| Area | Current code | Consequence |
|---|---|---|
| Login route | `src/server.xi:337-355` (`route_id == 4`) validates only `user` (1..64 chars, `src/schema.xi:52`), then calls `sessions.session_create(user, ttl)` and returns `{ok,user,sid,csrf}` plus `sid`/`csrf` cookies. | Any caller who names a user gets a valid session. No credential is requested or checked. The `sid` is also exposed in the JSON body (`src/server.xi:349`). |
| Session store | `src/session.xi:28` (`s_stores`), `session_init` `:46`, `session_create` `:57`, `session_get` `:71`, `session_drop` `:80`, cookie helpers `:102-143`. Backed by `xiom.session 0.1.0` (`C:\Users\lefte\AppData\Local\xiom-pulse-home\packages\xiom-session-0.1.0\xiom-session\src\session.xi:269` create, `:427` rotate, `:489` cookie header). | 128-bit lowercase-hex ids from `crypto.secure_random_bytes(16)`; absolute TTL; in-memory only, so sessions die on restart and are per-worker. No authentication marker on the entry. |
| CSRF | `src/server.xi:1020` rejects mutating requests only when a `sid` cookie exists and `X-CSRF-Token` does not match. Token generation `src/session.xi:125`; validation `:140`; package impl `...\xiom-http-middleware-0.1.0\xiom-http-middleware\src\middleware.xi:263` (16 CSPRNG bytes, constant-time compare). | Login is unauthenticated and therefore outside the session-CSRF gate. Login CSRF (forcing a victim into an attacker-owned account) is not covered; there is no Origin/Referer check on login. |
| JWT mint | `src/server.xi:376-395` (`route_id == 7`) validates only `user` and signs `sub`/`iat`/`exp` with `config.cfg_jwt_secret()`. | The same credential bypass exists for bearer tokens; fixing only the cookie login would leave S-08 open. |
| Rate limiting | `src/ratelimit.xi:19-73` (one global token bucket keyed `"global"`), `:91-300` (per-route policies). Header comment `src/ratelimit.xi:6-9` records why there is no per-client key (`socket_peer_addr` is a stdlib stub). Config `src/config.xi:50,57,64`; gate order `src/server.xi:1032-1053`. | There is no login-specific policy and no per-IP limit. A 600k-iteration PBKDF2 login would be CPU-amplifiable if it were added without a login rate policy. |
| Audit/log | `audit_event` `src/server.xi:861-878` writes `ts rid method target status`; access log `:853-859` writes no body. | Safe today because no secret is logged; the auth design must keep it that way and add explicit login outcomes. |
| User/credential store | None. `src/store.xi` is an event log (`store_init :123`, `store_append :145`, `store_valid_records :172`, `store_compact :294`), not a credential store. | New storage and schema are required. |

## 2. Decision

**Recommended primitive: PBKDF2-HMAC-SHA256 (RFC 8018), 32-byte derived
key, 16-byte per-user random salt, 600,000 iterations minimum.**

Call the real, in-tree RFC 2898 implementation, not a name-alike:

- `xiom.crypto.hash.crypto_hash_pbkdf2_sha256(password, salt, iterations, len)`
  at `...\xiom-0.65.6\lib\xiom\crypto\hash.xi:803`.
- Equivalent implementations exist but must not be mixed:
  `xiom.crypto.kdf.pbkdf2` (`...\crypto\kdf.xi:38`),
  `xiom.crypto.kdf.pbkdf2_hmac_sha256` (`kdf.xi:88`), and the flat
  `xiom.crypto.pbkdf2(password: Str, ...)` (`...\crypto\crypto.xi:2076`).
  Pick **one** (recommended: `crypto_hash_pbkdf2_sha256`) and route every
  enroll, verify, and rehash through it.

Supporting primitives that already exist:

- Constant-time byte compare:
  `xiom.crypto.mac.constant_time_eq` (`...\crypto\mac.xi:392`) or
  `xiom.crypto.constant_time_compare` (`...\crypto\crypto.xi:2247`). Use a
  byte comparator, never `Str ==`.
- CSPRNG bytes: `xiom.crypto.rng_crypto.crypto_random_bytes`
  (`...\crypto\rng_crypto.xi:39`) and its delegate
  `xiom.crypto.secure_random_bytes` (`...\crypto\crypto.xi:2231`).
  `xiom.rand.random_bytes_crypto` (`...\xiom\rand\rand.xi:579`) is the
  same source. `secure_random_bytes` documents a degraded no-OS fallback;
  a short or failed draw must be treated as **503 auth unavailable**, not
  as a usable salt.
- SHA-256/HMAC are real implementations (`...\crypto\crypto.xi:1127`),
  but their test probe records a link dependency on
  `xiom_sha256_hash`: `tests/probes/probe_crypto.xi:5-11` (the old
  `XIOM_RUNTIME_DIR` A/B). Any PBKDF2 gate must run the same probe on the
  pinned toolchain (`toolchain-pins.json`, compiler v0.65.6) before the
  auth tests.

### 2.1 Parameters

| Parameter | Value | Rule |
|---|---|---|
| Algorithm tag | `pbkdf2-sha256` | Versioned in every record; unknown tags are refused, never guessed. |
| Iterations | 600,000 | OWASP Password Storage Cheat Sheet current guidance for PBKDF2-HMAC-SHA256. Store the value per record so old hashes stay verifiable. `PULSE_PASSWORD_ITERATIONS` may raise it; values below 600,000 are a configuration error (see §8/§10). |
| Salt | 16 random bytes, lowercase hex (32 chars) | Fresh per user and per rehash. Never global, never reused, never derived from the username. |
| Derived key length | 32 bytes, lowercase hex (64 chars) | Fixed so the constant-time compare always sees equal-length inputs. |
| Encoding | Lowercase hex in a JSONL record | Avoids a base64 dependency; hex is easy to inspect and truncate-detect. |
| Password input | Byte-exact UTF-8, 1..1024 bytes | No trimming, no Unicode normalization. The cap bounds CPU/memory; >1024 is 400. |
| Username | 1..64 bytes, exact match | Keep the current `src/schema.xi:52` bound. No case folding or Unicode normalization unless the product later defines canonical usernames. |

### 2.2 Performance gate (important)

The in-tree PBKDF2 is a pure-XIOM loop over `crypto.hmac_sha256`; at
600,000 iterations it performs about 1.2M SHA-256 operations plus XIOM
loop overhead. It must be benchmarked on the release runner **before**
the feature is called production-ready. Gate:

- Target p50 ≤ 250 ms and p95 ≤ 500 ms per verify on release hardware
  with the pinned v0.65.6 toolchain and one user record.
- If 600,000 cannot meet the budget, the correct action is a vetted
  native/packaged KDF (see §11) or a vetted libcrypto binding, **not** a
  silent reduction of the iteration count. A reduction below OWASP
  guidance is a release blocker, not a tuning knob.
- The login route must have a rate policy before this CPU cost is
  exposed; otherwise the feature is a denial-of-service amplifier.

### 2.3 Explicitly rejected

| Rejected | Why |
|---|---|
| Plaintext password storage | Direct credential compromise on any file read. |
| Unsalted hash | Rainbow tables, identical-password correlation. |
| Single SHA-256 / salted fast SHA-256 | Far too fast for password guessing; a GPU tests billions/sec. |
| MD5, SHA-1, CRC/FNV/Murmur/xxHash | Non-cryptographic or collision-broken; not password KDFs. |
| `xiom.crypto.kdf.argon2id` / `xiom.crypto.argon2` | **Not Argon2.** Their own headers call them documented approximations built from PBKDF2 with cost-scaled iterations (`...\crypto\kdf.xi:17-19,402-421`; `...\crypto\crypto.xi:2136-2147`). They do not implement RFC 9106 memory-hardness and must not be labeled Argon2. |
| `xiom.crypto.kdf.bcrypt` | Also an approximation, not OpenBSD bcrypt (`kdf.xi:426-440`). |
| `xiom.password` v0.1.2 | Registry description: "Password strength scoring and structural checks (no crypto, no dictionaries)" (`xiom pkg info xiom.password`). Not a hash. |
| Client-side hashing as the only protection | The server would still receive a reusable equivalent; it does not replace server-side KDF storage. |
| Reversible encryption / pepper-only | Key compromise yields all passwords; a pepper may be added *in addition* to a salted KDF, never instead of it. |

### 2.4 Why not Argon2id now

`xiom pkg search argon2`, `scrypt`, `pbkdf`, `kdf`, and `xiom pkg info
argon2|bcrypt|pbkdf2|password` return no vetted password-hash package;
the lane package home
(`C:\Users\lefte\AppData\Local\xiom-pulse-home\packages`) contains only
the manifest dependencies (`xiom-http`, `xiom-jwt`, `xiom-session`,
`xiom-http-middleware`, etc.) and no hash primitive. The stdlib names are
approximations (§2.3). Therefore Argon2id is **not** selectable today.
PBKDF2-HMAC-SHA256 is the release primitive, and the record format below
keeps the algorithm tag so a future vetted Argon2id can be introduced by
rehash-on-login.

## 3. Credential store

### 3.1 Module and file

New module `xiom.pulse.users` in `src/users.xi`, registered in the
`package.xi` `modules` list (`package.xi:22`). It follows the existing
PULSE discipline: every `xiom.crypto`/`xiom.kv`/`xiom.sqlite` call stays
inside this module, and any package aggregate lives in a `Vec` holder,
not at module scope (the crash class documented in
`docs/COMPILER-FINDINGS-PULSE.md` C-PULSE-06/C-PULSE-09 and the header of
`src/session.xi:7-11`).

Storage: a JSONL file, one JSON object per line, append-only for creates
and rehashes; the reader takes the **last valid record** for a user.

- Default path: `pulse-users.jsonl` in the process working directory
  (mirrors `PULSE_STORE_PATH` at `src/config.xi:346`).
- New config: `PULSE_USERS_PATH` (`cfg_users_path()`), also settable via
  the `PULSE_CONFIG` JSON loader (`src/config.xi:239-266`, key
  `users_path`).
- `users_init(path)` creates the file with mode 0600 on Unix (directory
  0700) and validates every readable record; a malformed file does not
  crash the server, but login fails closed (§7).
- `users_compact(path)` is an offline/admin operation: write a temp file
  with one latest record per user, `io.rename` it into place (the same
  atomic-rename idea as `src/store.xi:294` and `src/audit.xi` rotation).
  Do not compact on the request path.
- Concurrency: appends use `io.append_line_sync` (same mechanism as the
  audit path, `src/server.xi:869`), which is append-atomic for normal
  line sizes. Compaction is single-writer and takes an exclusive lock
  file; runtime rehash only appends, so multiple workers do not rewrite
  each other's records. Last-valid-record-wins makes concurrent appends
  deterministic.
- File permissions: 0600 Unix, restricted ACL on Windows; the file must
  never be in `resources/`, `dist/`, or a release archive, and must be
  added to `.gitignore`.
- Scale: linear scan is acceptable for the current small user count; a
  per-worker in-memory map (again a `Vec` holder) can be loaded at
  startup and refreshed on file mtime change. If the deployment exceeds a
  documented threshold (recommend 10,000 users), move the backend to
  `xiom.sqlite`/`xiom.kv` behind the same `users_*` API; do not change
  the HTTP contract.

### 3.2 Record schema

One JSON object per line (data schema, not code):

```json
{"kind":"user","v":1,"user":"alice","alg":"pbkdf2-sha256","it":600000,"dklen":32,"salt":"<32 lowercase hex>","hash":"<64 lowercase hex>","status":"active","created_at":1762490000,"updated_at":1762490000,"pwd_changed_at":1762490000}
```

Rules:

- `kind` must be `user`; `v` must be `1`.
- `alg` must be `pbkdf2-sha256`; anything else is refused (no
  opportunistic fallback to SHA-256/MD5/plaintext).
- `it` must be > 0; the verifier accepts legacy lower values but
  rehashes on successful login (§9). A value below the current floor is
  **not** accepted for new records.
- `dklen` must be 32; `salt` must be exactly 32 lowercase hex chars and
  `hash` exactly 64 lowercase hex chars. Anything else disables that
  record (login fails closed; do not truncate or pad).
- `status`: `active` or `disabled`. Disabled returns the same generic 401
  as bad credentials.
- Unknown fields are ignored for forward compatibility; unknown `v`/`alg`
  are not guessed.
- No field may contain the password, a password-derived "hint", the JWT
  secret, a pepper, or a session id.

### 3.3 Provisioning

There is no public registration route in this design. Add an admin
command/script (proposed `scripts/user_add.ps1` / `scripts/user_add.sh`
or a `pulse user add` CLI subcommand) that:

1. reads the password from a secure prompt or stdin (never argv, never a
   shell history, never an environment variable),
2. draws a 16-byte salt from `crypto_random_bytes`,
3. derives with the current policy via the single canonical PBKDF2 call,
4. appends the record atomically and verifies it reads back,
5. prints only the username and parameters.

Until at least one active record exists, `POST /api/session/login` and
`POST /api/token` return **503 `auth_not_configured`** (fail closed). The
server must never fall back to the old user-only behavior.

## 4. Login flow

Route: `POST /api/session/login`, `src/server.xi:337-355` (route id 4,
registered at `src/router.xi:107`). Keep the path and `route_id`; change
the contract to require a credential.

### 4.1 Request contract

Body JSON:
`{"user":"<1..64 bytes>","password":"<1..1024 bytes>"}`.

- Validate both fields with `src/schema.xi` (`schema_string` at
  `src/schema.xi:52`) before touching the store or crypto. Missing,
  wrong-type, empty, oversized, or invalid JSON is `400 invalid_request`.
- Do not echo either field in the error body or logs. Do not put the
  password in a query string (the access log already redacts query
  credentials, but the login credential must be body-only).
- Convert the password `Str` to bytes with `slice.str_bytes` (the helper
  already used for the JWT secret at `src/server.xi:388`). The conversion
  must be byte-exact.

### 4.2 Verification sequence

1. Look up the exact `user` in the loaded credential map (no `user`
   existence signal yet).
2. Select the record, or a fixed **dummy record** with the current
   policy's salt/iterations/dklen when the user is unknown or disabled.
   The dummy record is generated once at startup from CSPRNG bytes and is
   never written to disk.
3. Derive once:
   `candidate = crypto_hash_pbkdf2_sha256(password_bytes, salt, it, 32)`.
   Always derive, including unknown/disabled/locked users.
4. Compare `candidate` with the stored 32-byte hash using
   `constant_time_eq`/`constant_time_compare`. Never compare hex strings
   with `==`.
5. On failure: record the failure (§6), write the audit outcome, return
   `401 invalid_credentials` with the generic message.
6. On success:
   - `old_sid = sessions.session_id_from_cookie(cookie_header)`; if
     non-empty, `sessions.session_drop(old_sid)` (fixation defense).
   - `sid = sessions.session_create(user, ttl)` (`src/session.xi:57`);
     if it returns `""`, return 503/500 without setting cookies.
   - `csrf = sessions.csrf_new_token()` (`src/session.xi:125`); if it
     returns `""`, do not issue a half session.
   - Set `Set-Cookie` for `sid` (`sessions.session_cookie_header`,
     `src/session.xi:102`; package header is
     `Path=/; HttpOnly; SameSite=Lax; Max-Age=...` plus `Secure` when
     requested, package `:489-503`). PULSE currently passes
     `secure=false` at `src/session.xi:103`; add
     `PULSE_COOKIE_SECURE=1` (set in production behind TLS) and pass
     `true`. Do not infer `Secure` from untrusted forwarding headers.
   - Set the rotated CSRF cookie (`src/session.xi:133`) and align its
     `Max-Age` with the session TTL; today `csrf_cookie_header` hardcodes
     `Max-Age=3600` while `PULSE_SESSION_TTL` is configurable
     (`src/config.xi:422`), which can leave a stale CSRF cookie.
   - Return `{ok:true,user,csrf}`. **Remove `sid` from the JSON body**
     (currently `src/server.xi:349`); the HttpOnly cookie is the only
     place the session id belongs. Keep `csrf` in the body only because
     the double-submit client needs to read it (the CSRF cookie is not
     HttpOnly by design).
   - Reset the per-user failure ledger and write a `login_ok` audit line.
   - If the record's `it` is below `PULSE_PASSWORD_ITERATIONS` or its
     `alg`/`dklen` differs from policy, derive a new salt/hash and append
     a rehash record (§9). A rehash write failure is logged and metered;
     it must never store the plaintext and must not silently downgrade.

### 4.3 JWT route parity

`POST /api/token` (`src/server.xi:376-395`) must call the same
verification function before signing. Refactor the check into one
`users_authenticate(user, password) -> AuthResult` used by both routes;
do not duplicate the logic. Without this, an attacker can mint a bearer
token for any user and S-08 is not closed.

### 4.4 Session semantics

- Session fixation: login always creates a fresh 128-bit id; any
  pre-login `sid` is dropped. A `sid` supplied in the body or query is
  ignored. The CSRF token is also fresh.
- Store an authentication marker in the session (for example
  `session_set(sid, "auth", "pwd", now)` and `auth_at`) so a future
  persistent store can reject pre-auth entries. `xiom.session` already
  provides entry storage (`session.xi:326`) and `session_rotate`
  (`:427`) for privilege changes.
- Current store is in-memory and per-worker (`src/session.xi:28`).
  Multi-worker deployments therefore need sticky sessions or a shared
  session store; login on worker A and `/api/me` on worker B will 401.
  This is an existing limitation (`docs/N-PORT-EDGE.md:75`) and a release
  gate for any multi-worker claim.

## 5. CSRF integration

- The existing gate (`src/server.xi:1020`) correctly protects
  authenticated mutating requests (logout, uploads, events, game
  commands). Keep it, and keep the constant-time comparison.
- Login is unauthenticated, so the session-CSRF gate cannot protect it.
  Add a same-origin check on login: when the `Origin` header is present,
  require it to match the configured site/CORS origin
  (`PULSE_CORS_ORIGIN`, `src/config.xi:197`); otherwise return
  `403 csrf`. When `Origin` is absent (non-browser clients), allow but
  log the absence. Do not rely on `SameSite=Lax` alone for login CSRF.
- Do not accept `Origin: *` with credentials; the CORS module
  (`src/cors.xi`) and `docs/DEPLOYMENT.md` already state the
  allowlist-with-credentials rule.
- Logout (`src/server.xi:368-375`) must clear both cookies: the session
  (`sessions.session_expired_cookie_header`, `src/session.xi:108`) and
  the CSRF cookie. Today only `sid` is cleared.
- Rotate the CSRF token on login and on any privilege change. The
  middleware validates in constant time (`...\middleware.xi:280`).

## 6. Rate limiting and lockout

### 6.1 Route-level rate policy

Add a login policy to `PULSE_RATE_ROUTES` (`src/config.xi:64`,
`src/ratelimit.xi:91-300`), for example:

`POST /api/session/login=1/5,POST /api/token=1/5`

(1 request/second, burst 5 per worker). This is additive to the global
bucket (`src/ratelimit.xi:38`) and runs in the existing gate order
(`src/server.xi:1032-1053`). Startup/`--check-config` should warn when
auth is enabled and neither login route has a policy.

### 6.2 Per-account failure ledger

A dedicated ledger, keyed by the **submitted** username (whether or not
it exists), so unknown-user probing and known-user probing behave
identically:

| Field | Meaning |
|---|---|
| `key` | exact submitted user bytes (bounded to 64) |
| `fails` | consecutive failures in the current window |
| `first_fail_ms` | start of the current window |
| `last_fail_ms` | most recent failure |
| `locked_until_ms` | 0 or the end of a lockout |

Config (env, plus `PULSE_CONFIG` keys):

- `PULSE_LOGIN_MAX_FAILS` default `5`.
- `PULSE_LOGIN_WINDOW_SECS` default `900`.
- `PULSE_LOGIN_LOCKOUT_SECS` default `900`.
- `PULSE_LOGIN_GLOBAL_MAX_FAILS` default a bounded aggregate (for
  credential-stuffing pressure that spreads across usernames).
- `PULSE_LOGIN_LEDGER_MAX` default `10000` entries; evict expired keys
  first, then the oldest, so random usernames cannot grow memory without
  bound.

Semantics:

- Failure within the window: increment `fails`.
- `fails >= PULSE_LOGIN_MAX_FAILS`: set
  `locked_until_ms = now + lockout`. Return
  `429 too_many_attempts` with `Retry-After` (seconds).
- During lockout: still perform one PBKDF2 draw (real record if present,
  dummy otherwise) so a locked account is not distinguishable by CPU
  time, then return 429.
- Success: clear the key's counter.
- Unknown users are counted and locked exactly like known users. This
  avoids enumeration but enables targeted lockout DoS; document the
  trade-off. For a public high-value deployment, prefer progressive
  delay (short 30s lockout at 5, longer at higher counts) or
  `PULSE_LOGIN_LOCKOUT=off` plus the route/global rate limits. Do not
  make lockout indefinite.
- The ledger is in-memory per worker, like sessions. With N workers the
  effective attempt budget is multiplied; the global/route bucket bounds
  aggregate traffic, but a shared ledger (SQL/KV) is required for a
  strict cross-worker lockout. State this explicitly in the deployment
  docs.

### 6.3 Per-IP limiting (blocked dependency)

`src/ratelimit.xi:6-9` records that per-client keys are impossible today
because `socket_peer_addr` is a stdlib stub. Do not fake an IP from
`X-Forwarded-For` (untrusted). Per-IP throttling is a documented gap
until the net/stdlib lane exposes the peer address and the
trusted-proxy configuration is defined. Until then: per-username ledger
+ global/route token buckets.

## 7. Timing behavior

Goal: an observer cannot distinguish (a) a valid user with a wrong
password, (b) an unknown user, (c) a disabled user, or (d) a locked user
by response time or body.

Rules:

1. Always perform exactly one PBKDF2 derivation with the **current**
   policy parameters before returning 401/429. The dummy record uses the
   same `it`/`dklen` as the policy.
2. Do not return early on lookup failure. Load the credential map at
   startup (and on mtime change) so disk access does not reveal the
   lookup result; a per-user file stat/scan must not precede the KDF.
3. Compare fixed-length 32-byte digests with
   `constant_time_eq`/`constant_time_compare`. Note that both helpers
   return early on a length mismatch; because the design fixes `dklen`
   at 32 and validates the record before use, that branch is not
   reachable in the verification path.
4. Keep the success path's extra work (session create, CSRF, cookie
   rendering) separate from the failure path; do **not** add a random
   sleep (it is observable and hurts throughput). Equal KDF work is the
   defense.
5. Test determinism: expose a test-only/metric counter (`pulse_auth_kdf_total`)
   and assert it increments on unknown/disabled/locked attempts. A
   statistical timing test is also useful but must be non-gating or use
   a wide tolerance because CI scheduling is noisy.

## 8. Error responses

Use the existing envelope (`envelope.error_body`, `src/server.xi:332`
and the `xiom.pulse` envelope package).

| Status | Code | When | Headers / notes |
|---|---|---|---|
| 400 | `invalid_request` | missing/wrong-type/empty/oversized `user` or `password`; invalid JSON | No reflection of input. |
| 401 | `invalid_credentials` | wrong password, unknown user, disabled user | Identical body and headers for all three. Message: `invalid username or password`. No `Set-Cookie`. |
| 403 | `csrf` | login `Origin` present and not allowed; authenticated mutating request missing/mismatched `X-CSRF-Token` | Existing CSRF path (`src/server.xi:1020`). |
| 429 | `too_many_attempts` | per-account lockout or route/global bucket | `Retry-After: <seconds>`; same for known and unknown usernames. |
| 503 | `auth_not_configured` | no user store file / no active records | Fail closed; never fall back to user-only login. |
| 503 | `auth_unavailable` | unreadable store, CSPRNG failure, PBKDF2/link failure | Fail closed; log a sanitized error. |
| 500 | `internal_error` | unexpected derive/write failure | Generic; no hash, salt, or password in the body or logs. |

Never return 404/409/422 in a way that distinguishes an existing user,
never return the hash/salt/iterations, and never log the password.
The access log does not include bodies (`src/server.xi:853-859`); add a
dedicated auth audit line with `event` (`login_ok`/`login_failed`),
`user`, `reason` (`bad_password`/`unknown_user`/`disabled`/`locked`),
`rid`, and status only. Reuse the audit rotation
(`src/audit.xi`, `src/server.xi:861-878`) and never write a secret.

## 9. Migration, backfill, and rehash

There is no existing password data to migrate: current login trusts a
username only (`docs/FEATURE-TESTS.md:167`). The migration is therefore a
**credential provisioning cutover**, not a data conversion.

1. Deploy the users module/file and config; do not enable the login
   routes' success path yet.
2. Provision accounts with the admin command (§3.3). Never import
   plaintext; if an external system is the source, derive PBKDF2 from the
   plaintext in a trusted offline process and write only the salt/hash.
3. Restart PULSE. The in-memory session store is cleared
   (`sessions.session_init`, `src/server.xi:1447`, `src/session.xi:46`),
   so no pre-auth session survives. If session persistence is added
   later, gate on the `auth` marker and invalidate sessions without it.
4. Enable the login/JWT verification path; run the test matrix (§10).
5. Rehash on login: any active record with `it` below the current policy
   (or an older algorithm tag) is rehashed with a fresh 16-byte salt and
   the current parameters after a successful verify. Append the new
   record atomically; the old record stays as history until compaction.
6. Legacy formats (`sha256`, `md5`, unsalted, plaintext) are **not**
   verified. Mark them disabled and require a password reset through the
   admin path; do not add a compatibility verifier.
7. Run `users_compact` offline after the rehash window; confirm one
   latest record per user and re-run the hash-at-rest test.

Rollout must not include an insecure escape hatch. If an operational
escape is unavoidable for local development, it must be an explicit
non-production flag that the release build rejects and that logs a loud
warning; default behavior is fail closed.

## 10. Test matrix

Existing harnesses to extend (do not duplicate them):

- `tests/test_app.xi` in-process route harness (`route_req` at
  `tests/test_app.xi:48`; current user-only login assertions at
  `:408-419` must be replaced).
- `scripts/http_smoke.ps1` live cookie flow (`:200-221`: login, me,
  logout). This currently logs in with user-only and must be updated.
- `scripts/gate_order.py` for the frozen CSRF/rate gate order.
- `scripts/rate_smoke.ps1` for 429/`Retry-After`.
- `tests/probes/probe_crypto.xi` pattern for the PBKDF2 KAT probe
  (add `tests/probes/probe_pbkdf2.xi`).
- `.github/workflows/ci.yml` suites/smoke gates (`:144-155`), rate gate
  (`:194-197`), package probes (`:213-216`).
- `docs/RELEASE-CHECKLIST.md` and `scripts/release.ps1` for the release
  gate.

| ID | Test | Harness | Assertion | Gate |
|---|---|---|---|---|
| A-01 | Wrong password → 401 | `test_app` + `http_smoke` | 401, `invalid_credentials`, identical body to unknown user, no `Set-Cookie: sid`, no session created | P0 |
| A-02 | Correct password → 200 | `test_app` + `http_smoke` | 200, `sid` cookie `HttpOnly; SameSite=Lax`, `csrf` cookie, `{ok,user,csrf}`, no `sid` in body, `/api/me` 200 | P0 |
| A-03 | Unknown user parity | `test_app` | Same status/body/headers as A-01; KDF counter increments; no 404/409 | P0 |
| A-04 | Hash at rest | new `test_auth` + file inspection | No field equals the password; salt is 32 hex, hash 64 hex, `alg=pbkdf2-sha256`, `it>=600000`, `dklen=32`; file mode 0600 on Unix; no plaintext anywhere in the line | P0 |
| A-05 | Tamper/corruption | new `test_auth` | Flip hash/salt/params → login 401; truncated JSON line → last valid record or 503, never crash/authenticate; unknown `alg`/`v` → fail closed | P0 |
| A-06 | Timing / equal work | new `test_auth` + metric | Deterministic KDF-call counter increments for wrong/unknown/disabled/locked; statistical medians within 20% (diagnostic, non-gating) | P0 (counter), P2 (statistics) |
| A-07 | Session fixation | `test_app` | Pre-set `sid=attacker`; login issues a different id; old id invalid at `/api/me`; CSRF token rotates; body/query `sid` ignored | P0 |
| A-08 | Lockout | new `test_auth` + `rate_smoke` | N failures → 429 + `Retry-After`; correct password during lockout still 429; after expiry 200; success resets; unknown-user attempts counted; ledger bounded | P0 |
| A-09 | CSRF on login/logout | `gate_order.py` + `http_smoke` | Cross-site `Origin` on login → 403; same-origin allowed; logout without token 403; logout clears both cookies | P0 |
| A-10 | JWT route parity | `test_app` + `http_smoke` | `POST /api/token` wrong password 401; correct 200; no user-only mint | P0 |
| A-11 | PBKDF2 KAT | new `probe_pbkdf2.xi` | RFC 7914 §11 PBKDF2-HMAC-SHA256 vectors (e.g. P=`passwd`, S=`salt`, c=1/2/4096, dkLen=64) and RFC 4231 HMAC vectors pass on all gating platforms | P0 |
| A-12 | CSPRNG salts | new `test_auth` | 16-byte length, 10k distinct salts, no repeats; forced RNG failure → 503, not a weak salt | P0 |
| A-13 | Rehash/migration | new `test_auth` | `it=1000` record verifies once and is rewritten to 600000 with a new salt; legacy/plaintext record refused; unknown alg refused | P0 |
| A-14 | Config validation | `--check-config` | `PULSE_PASSWORD_ITERATIONS < 600000` is an error; missing `PULSE_USERS_PATH`/store is reported; `PULSE_COOKIE_SECURE` and login rate policy are surfaced | P0 |
| A-15 | Oversize/DoS | `test_app` + fuzz | password 1025 bytes → 400; 1 MiB body cap already enforced (`src/server.xi:979-1002`); login rate policy returns 429 under burst | P0 |
| A-16 | Multi-worker | worker smoke | Document/verify per-worker session and lockout behavior; a multi-worker deployment without sticky/shared store is explicitly non-conforming | P1 |
| A-17 | Log/audit redaction | `test_app` + log inspection | Access and audit lines contain user/rid/status/reason only; no password, hash, salt, or session id | P0 |
| A-18 | Fail closed | `test_app` | Missing/empty/unreadable user store → 503 `auth_not_configured`/`auth_unavailable`; no user-only fallback | P0 |
| A-19 | Concurrency | new `test_auth` | Two simultaneous logins for one user do not lose a rehash record; two failures increment the ledger atomically; appends produce valid JSON lines | P1 |
| A-20 | Cookie flags/TTL | `http_smoke` | `HttpOnly`, `SameSite=Lax`, `Secure` when configured; CSRF cookie Max-Age matches session TTL; logout `Max-Age=0` for both | P0 |

A-01, A-02, A-04, A-05, A-06 (counter), A-07, A-08, A-09, A-10, A-11,
A-13, A-14, A-15, A-17, A-18, and A-20 are release-blocking. A-06
statistics, A-16, and A-19 may be non-gating with a documented reason,
but A-16 must be called out in the deployment notes.

## 11. Dependency ask

### 11.1 What exists

PBKDF2-HMAC-SHA256 already exists and is real RFC 2898 code
(`crypto_hash_pbkdf2_sha256`, `...\crypto\hash.xi:803`), with a real
HMAC-SHA256 (`...\crypto\crypto.xi:1127`, `...\crypto\mac.xi:139`), a
constant-time byte compare (`...\crypto\mac.xi:392`), and a CSPRNG
(`...\crypto\rng_crypto.xi:39`). No new package is required for the
release primitive.

### 11.2 Exact ask to the packages lane (only if Argon2id is wanted)

Because no vetted Argon2id/bcrypt package exists (registry search and
`xiom pkg info` are empty; the lane home has none; the stdlib names are
approximations per `...\crypto\kdf.xi:17-19,402-440`), the following is
the exact packages-lane request for the preferred upgrade:

- **Package:** `xiom.argon2` (or `xiom.password-hash`) v0.1.0,
  MIT OR Apache-2.0, signed registry release, SBOM entry.
- **API:**
  - `Argon2Params` with `memory_kib`, `iterations`, `parallelism`,
    `salt_len`, `hash_len`.
  - `argon2id_hash(password: &Vec[UInt8], params: &Argon2Params) ->
    Result[Str, Str]` returning a PHC string
    `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>`.
  - `argon2id_verify(password: &Vec[UInt8], encoded: &Str) ->
    Result[Bool, Str]` with a constant-time comparison.
  - `argon2id_needs_rehash(encoded: &Str, params: &Argon2Params) ->
    Bool`.
- **Defaults:** m=19456 KiB (19 MiB), t=2, p=1, salt=16 bytes,
  hash=32 bytes (OWASP minimum). Salt drawn internally from
  `xiom.crypto.secure_random_bytes` or an injected RNG for tests.
- **Correctness:** RFC 9106 v1.3; the RFC 9106 §5 known-answer vectors;
  differential tests against the reference `argon2` CLI for a matrix of
  parameters; property tests for encode/verify/rehash; rejection tests
  for malformed PHC strings.
- **Operational:** no shell/network calls; no unpinned dynamic loader
  (if FFI is unavoidable, vendor and pin the reference implementation);
  deterministic under test; best-effort secret zeroization; documented
  memory use and a configurable cap; benchmarks on the five release
  platforms.
- **Migration:** `argon2id_needs_rehash` + the `alg` tag lets PULSE
  rehash PBKDF2 records on successful login without a flag day.

If a vetted package lands, PULSE may migrate by changing the
`PULSE_PASSWORD_ALG` default and rehashing on login. Until then, PBKDF2
is the only approved primitive.

### 11.3 Adjacent asks (not packages-lane blockers)

- Net/stdlib lane: expose the peer address (`socket_peer_addr`) so
  per-IP login throttling and trusted-proxy configuration are possible
  (currently blocked per `src/ratelimit.xi:6-9`).
- stdlib lane: rename or explicitly mark
  `xiom.crypto.kdf.argon2id`/`bcrypt` and `xiom.crypto.argon2` as
  approximations/non-compatible to prevent another project from
  selecting them by name (`...\crypto\kdf.xi:402-440`).

## 12. Release gating (S-08)

S-08 must remain `M`/open in `docs/PARITY-MATRIX.md:88` and the evidence
row in `docs/FEATURE-TESTS.md:167` until all of the following are true.
This design does not change either status.

1. Code and tests land for §4-§10; the current user-only assertions
   (`tests/test_app.xi:408-419`, `scripts/http_smoke.ps1:200-221`) are
   replaced, not merely bypassed.
2. `probe_pbkdf2` KAT and the `probe_crypto` link probe are green on
   every gating platform in `.github/workflows/ci.yml` (Linux x64/arm64,
   Windows x64; macOS per the current release matrix).
3. `PULSE_PASSWORD_ITERATIONS >= 600000`, the login routes have a rate
   policy, and `--check-config` rejects a weaker setting.
4. The hash-at-rest test reads a real provisioned file and finds no
   plaintext, no weak algorithm, and mode 0600 (Unix).
5. The release artifacts do not contain `pulse-users.jsonl`, a default
   credential, a dev JWT secret, or any password in logs/audit
   (`scripts/release.ps1`, `docs/RELEASE-CHECKLIST.md`).
6. The multi-worker limitation (per-worker session/lockout store) is
   documented in `docs/DEPLOYMENT.md`/`docs/N-PORT-EDGE.md`; a
   multi-worker deployment is either sticky/shared-store or explicitly
   non-conforming.
7. The independent review retests the auth/session scope
   (`docs/SECURITY-AUDIT-SCOPE.md` §2 "Auth and session") before the
   1.0 claim. No "audited" claim is made by this document.

## 13. What exists vs. what must be added

| Exists and is reusable | Must be added |
|---|---|
| Session store and cookie rendering (`src/session.xi`, `xiom.session`) | `src/users.xi` credential module and store backend |
| CSRF token + constant-time validation (`src/session.xi:125-143`, `xiom.http.middleware`) | `password` field, schema validation, and verification in route id 4 |
| Global/route token buckets (`src/ratelimit.xi`) | Login-specific rate policy + per-account failure/lockout ledger |
| JSONL append/compact and audit rotation (`src/store.xi`, `src/audit.xi`) | Credential record schema, provisioning command, atomic rehash |
| PBKDF2-HMAC-SHA256 (`...\crypto\hash.xi:803`), constant-time compare (`...\crypto\mac.xi:392`), CSPRNG (`...\crypto\rng_crypto.xi:39`) | Dummy-record generation, RNG failure handling, performance gate |
| Schema validation (`src/schema.xi`) and error envelope (`xiom.pulse.envelope`) | Generic auth errors, Origin check, login/JWT parity, no-`sid`-in-body |
| Config/env loader and `--check-config` (`src/config.xi:239-610`) | `PULSE_USERS_PATH`, iteration floor, lockout knobs, `PULSE_COOKIE_SECURE` |
| Test harnesses (`tests/test_app.xi`, `http_smoke`, `gate_order`, `rate_smoke`) | Auth unit/HTTP/KAT/timing/lockout/fixation tests (A-01..A-20) |

Known gaps that remain after this design unless separately addressed:
a vetted Argon2id package, per-IP throttling (peer-address stub), a
persistent/shared session store, and a shared cross-worker lockout
ledger.

## 14. Source index

- `src/server.xi:337-355` login; `:356-367` me; `:368-375` logout;
  `:376-395` token; `:853-878` access/audit log; `:977-1067` gate order;
  `:1020` CSRF; `:1032-1053` rate; `:1447` session init.
- `src/session.xi:28` store holder; `:46` init; `:57` create; `:71`
  get; `:80` drop; `:102-143` cookie/CSRF helpers.
- `src/ratelimit.xi:6-9` per-client-key limitation; `:19-73` global
  limiter; `:91-300` route policies.
- `src/config.xi:50,57,64` rate; `:197` CORS; `:202` CSRF; `:239-266`
  `PULSE_CONFIG` loader; `:309` audit; `:331` JWT secret; `:346` store
  path; `:422` session TTL; `:504-610` validation.
- `src/store.xi:123,145,172,294` init/append/read/compact.
- `src/router.xi:102-130` route table; `src/schema.xi:52,82,139`
  validation; `src/audit.xi` rotation.
- `package.xi:22` module list; `toolchain-pins.json` compiler v0.65.6.
- `...\xiom-0.65.6\lib\xiom\crypto\hash.xi:803` PBKDF2;
  `...\crypto\crypto.xi:1127` HMAC-SHA256; `:2231` CSPRNG; `:2247`
  constant-time compare; `...\crypto\mac.xi:392` constant-time eq;
  `...\crypto\rng_crypto.xi:39` random bytes;
  `...\crypto\kdf.xi:17-19,38,88,402-440` aliases and approximation
  warnings.
- Lane packages: `...\xiom-pulse-home\packages\xiom-session-0.1.0\...\
  session.xi:269,427,489`; `...\xiom-http-middleware-0.1.0\...\
  middleware.xi:263,280`.
- Tests/gates: `tests/test_app.xi:48,408-419`;
  `tests/probes/probe_crypto.xi:5-11`; `scripts/http_smoke.ps1:200-221`;
  `scripts/gate_order.py`; `scripts/rate_smoke.ps1`;
  `.github/workflows/ci.yml:144-155,194-197,213-216`.
- Audit/status: `docs/FEATURE-TESTS.md:167`;
  `docs/PARITY-MATRIX.md:88`;
  `docs/SECURITY-AUDIT-SCOPE.md` §2;
  `docs/RELEASE-CHECKLIST.md`;
  `docs/COMPILER-FINDINGS-PULSE.md` C-PULSE-06/C-PULSE-09.
- External standards: RFC 8018 (PBKDF2), RFC 7914 §11
  (PBKDF2-HMAC-SHA256 vectors), RFC 4231 (HMAC vectors), RFC 9106
  (Argon2id), OWASP Password Storage Cheat Sheet (600,000 iterations
  for PBKDF2-HMAC-SHA256).
