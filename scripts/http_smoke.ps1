#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE HTTP smoke: start the compiled server, exercise every route with
# curl, QUIT, and verify the clean shutdown.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\http_smoke.ps1
# Exit code: 0 = all checks green, 1 = failed.
#
# NOTE: request bodies are passed to curl via --data-binary "@file" because
# PowerShell 5.1 strips embedded double quotes from arguments to native
# commands (a `{"a":1}` arg reaches curl as `{a:1}`).
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 8080,
    [string]$ServerExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app.exe" }
$base = "http://127.0.0.1:$Port"

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# --- CLI pre-flight (--version / --check-config) ----------------------------
$verOut = (& $ServerExe --version 2>&1 | Out-String)
$verRc = $LASTEXITCODE
$cfgOut = (& $ServerExe --check-config 2>&1 | Out-String)
$cfgRc = $LASTEXITCODE
$env:PULSE_PORT = "abc"
$cfgWarnOut = (& $ServerExe --check-config 2>&1 | Out-String)
$cfgWarnRc = $LASTEXITCODE
Remove-Item Env:PULSE_PORT -ErrorAction SilentlyContinue

$env:PULSE_PORT = "$Port"
$env:PULSE_CORS_ORIGIN = "*"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ServerExe
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$srv = New-Object System.Diagnostics.Process
$srv.StartInfo = $psi
$null = $srv.Start()
Start-Sleep -Milliseconds 900

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [string]$Haystack, [string]$Needle, [bool]$Want = $true)
    $has = $Haystack -like "*$Needle*"
    if ($has -eq $Want) {
        Write-Host "[PASS] $Name"
        $script:pass++
    } else {
        Write-Host "[FAIL] $Name (want '$Needle' present=$Want)"
        Write-Host "---- body ----"
        Write-Host $Haystack
        Write-Host "--------------"
        $script:fail++
    }
}

Check "cli version text" $verOut "xiom-pulse"
Check "cli version rc" "rc=$verRc" "rc=0"
Check "cli check-config text" $cfgOut "port="
Check "cli check-config rc" "rc=$cfgRc" "rc=0"
Check "cli check-config warns" $cfgWarnOut "warning:"
Check "cli check-config warn rc" "rc=$cfgWarnRc" "rc=0"

function Invoke-CurlPost {
    param([string]$Path, [string]$Body, [string]$CookieJar = "", [string[]]$ExtraHeaders = @())
    $f = Join-Path $env:TEMP ("pulse-body-" + [guid]::NewGuid().ToString("N") + ".json")
    Set-Content -LiteralPath $f -Value $Body -NoNewline
    try {
        $extra = @()
        if ($CookieJar) { $extra += @("-b", $CookieJar, "-c", $CookieJar) }
        $all = @("-s", "-i", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@$f") + $extra + $ExtraHeaders + @("$base$Path")
        return (curl.exe @all 2>&1 | Out-String)
    } finally {
        Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue
    }
}

function Invoke-CurlGet {
    param([string]$Path, [string]$CookieJar = "")
    $extra = @()
    if ($CookieJar) { $extra += @("-b", $CookieJar) }
    $all = @("-s", "-i") + $extra + @("$base$Path")
    return (curl.exe @all 2>&1 | Out-String)
}

# 1. GET /health
$r = curl.exe -s -i "$base/health" 2>&1 | Out-String
Check "health 200" $r "200 OK"
Check "health json" $r '{"status":"ok"}'
Check "date header" $r "Date: "

# 2. GET /api/version
$r = curl.exe -s -i "$base/api/version" 2>&1 | Out-String
Check "version 200" $r "200 OK"
Check "version name" $r '"name":"xiom-pulse"'
Check "version value" $r '"version":"0.1.2"'

# 3. POST /api/echo valid
$r = Invoke-CurlPost "/api/echo" '{"a":1}'
Check "echo 200" $r "200 OK"
Check "echo body" $r '{"echo":{"a":1}}'

# 4. POST /api/echo invalid
$r = Invoke-CurlPost "/api/echo" 'notjson'
Check "echo invalid 400" $r "400 Bad Request"
Check "echo invalid json" $r '"code":"invalid_json"'

# 4b. Transfer-Encoding: chunked decoded; gzip 501; TE+CL 400
$r = Invoke-CurlPost "/api/echo" '{"chunked":1}' -ExtraHeaders @("-H", "Transfer-Encoding: chunked")
Check "chunked 200" $r "200 OK"
Check "chunked echo body" $r '{"echo":{"chunked":1}}'
$r = Invoke-CurlPost "/api/echo" '{"x":1}' -ExtraHeaders @("-H", "Transfer-Encoding: chunked", "-H", "Content-Length: 7")
Check "te+cl rejected 400" $r "400 Bad Request"
$r = Invoke-CurlPost "/api/echo" '{"x":1}' -ExtraHeaders @("-H", "Transfer-Encoding: gzip")
Check "te gzip rejected 501" $r "501 Not Implemented"

# 5. 404
$r = curl.exe -s -i "$base/nope" 2>&1 | Out-String
Check "unknown 404" $r "404 Not Found"
Check "404 has rid" $r '"rid":"r-'

# 6. 405
$r = curl.exe -s -i -X DELETE "$base/health" 2>&1 | Out-String
Check "wrong method 405" $r "405 Method Not Allowed"

# 7. POST with a longer body (Content-Length framing)
$r = Invoke-CurlPost "/api/echo" '{"longer":"payload","n":42}'
Check "echo longer 200" $r "200 OK"
Check "echo longer body" $r '{"longer":"payload","n":42}'

# 7b. Expect: 100-continue (interim answered before the body)
$r = Invoke-CurlPost "/api/echo" '{"e":1}' -ExtraHeaders @("-H", "Expect: 100-continue")
Check "expect 100-continue 200" $r "200 OK"

# 8. Step 2: router param route + metrics
$r = Invoke-CurlGet "/api/items/42"
Check "item 200" $r "200 OK"
Check "item body" $r '{"item":"42"}'
$r = Invoke-CurlGet "/metrics"
Check "metrics 200" $r "200 OK"
Check "metrics text" $r "pulse_http_requests_total"
Check "metrics store gauge" $r "pulse_store_records"
Check "metrics app info" $r "pulse_app_info"
Check "metrics uptime" $r "pulse_uptime_seconds"

# 9. Step 2: cookie sessions
$cookieJar = Join-Path $env:TEMP ("pulse-cookies-" + [guid]::NewGuid().ToString("N") + ".txt")
$r = Invoke-CurlPost "/api/session/login" '{"user":"carol"}' -CookieJar $cookieJar
Check "login 200" $r "200 OK"
Check "login set-cookie" $r "Set-Cookie: sid="
Check "login csrf cookie" $r "Set-Cookie: csrf="
Check "login user" $r '"user":"carol"'
$csrfMatch = [regex]::Match($r, '"csrf":"([^"]+)"')
if ($csrfMatch.Success) { Check "login csrf body" "yes" "yes" } else { Check "login csrf body" "no" "yes" }
$csrfToken = $csrfMatch.Groups[1].Value
$r = Invoke-CurlGet "/api/me" -CookieJar $cookieJar
Check "me 200 with cookie" $r "200 OK"
Check "me user" $r '"user":"carol"'
$r = Invoke-CurlGet "/api/me"
Check "me 401 without cookie" $r "401 Unauthorized"
$r = Invoke-CurlPost "/api/session/logout" "" -CookieJar $cookieJar
Check "logout 403 without csrf" $r "403 Forbidden"
$r = Invoke-CurlPost "/api/session/logout" "" -CookieJar $cookieJar -ExtraHeaders @("-H", "X-CSRF-Token: $csrfToken")
Check "logout 200 with csrf" $r "200 OK"
Check "logout clears cookie" $r "Max-Age=0"
$r = Invoke-CurlGet "/api/me" -CookieJar $cookieJar
Check "me 401 after logout" $r "401 Unauthorized"
Remove-Item -LiteralPath $cookieJar -ErrorAction SilentlyContinue

# 10. Step 2: JWT HS256 issue + verify + tamper
$r = Invoke-CurlPost "/api/token" '{"user":"carol"}'
Check "token 200" $r "200 OK"
$tokMatch = [regex]::Match($r, '"token":"([^"]+)"')
if ($tokMatch.Success) { Check "token issued" "yes" "yes" } else { Check "token issued" "no" "yes" }
if ($tokMatch.Success) {
    $tok = $tokMatch.Groups[1].Value
    $r = Invoke-CurlPost "/api/token/verify" "{`"token`":`"$tok`"}"
    Check "token verify 200" $r "200 OK"
    Check "token verify body" $r '"ok":true'
    Check "token verify payload" $r '"payload":'
    # Append a char: deterministic 401 (replacing the last base64url char
    # is flaky -- trailing padding bits can decode to the same bytes).
    $tampered = $tok + "x"
    $r = Invoke-CurlPost "/api/token/verify" "{`"token`":`"$tampered`"}"
    Check "token tamper 401" $r "401 Unauthorized"
}

# 11. Step 3: JSONL event store routes
$r = Invoke-CurlPost "/api/events" '{"kind":"smoke","n":1}'
Check "events post 200" $r "200 OK"
Check "events post stored" $r '"stored":true'
$r = Invoke-CurlGet "/api/events/count"
Check "events count 200" $r "200 OK"
Check "events count body" $r '"count":'
$r = Invoke-CurlGet "/api/events"
Check "events list 200" $r "200 OK"
Check "events list body" $r '"events":'
$r = Invoke-CurlGet "/api/events?limit=1"
Check "events limit 200" $r "200 OK"
$r = Invoke-CurlGet "/api/events?kind=smoke"
Check "events kind 200" $r "200 OK"
Check "events kind body" $r "smoke"
$r = Invoke-CurlPost "/api/events/compact" ""
Check "events compact 200" $r "200 OK"
Check "events compact ok" $r '"ok":true'

# 12. App icon + landing page
$r = Invoke-CurlGet "/favicon.ico"
Check "favicon 200" $r "200 OK"
Check "favicon type" $r "Content-Type: image/x-icon"
Check "favicon length" $r "Content-Length: "
$r = Invoke-CurlGet "/"
Check "landing 200" $r "200 OK"
Check "landing title" $r "XIOM PULSE"
Check "landing html" $r "text/html"

# 12b. showcase assets (/assets/)
# NOTE: --etag-save/--etag-compare keep the quoted ETag inside curl; PS 5.1
# would strip the quotes from an -H "If-None-Match: \"...\"" argument.
$etagFile = Join-Path $env:TEMP ("pulse-etag-" + [guid]::NewGuid().ToString("N"))
$r = curl.exe -s -i --etag-save $etagFile "$base/assets/hello.txt" 2>&1 | Out-String
Check "assets 200" $r "200 OK"
Check "assets type" $r "Content-Type: text/plain"
Check "assets body" $r "XIOM PULSE static asset demo"
$r = curl.exe -s -i --etag-compare $etagFile "$base/assets/hello.txt" 2>&1 | Out-String
Check "assets 304" $r "304 Not Modified"
Remove-Item -LiteralPath $etagFile -ErrorAction SilentlyContinue
$r = curl.exe -s -i --path-as-is "$base/assets/../xiom.toml" 2>&1 | Out-String
Check "assets traversal 404" $r "404 Not Found"

# 12c. HEAD + CORS
$r = curl.exe -s -I "$base/health" 2>&1 | Out-String
Check "head 200" $r "200 OK"
Check "head content-length" $r "Content-Length: 15"
$r = curl.exe -s -i -H "Origin: http://example.test" "$base/health" 2>&1 | Out-String
Check "cors allow origin" $r "Access-Control-Allow-Origin: *"
$r = curl.exe -s -i -X OPTIONS -H "Origin: http://example.test" -H "Access-Control-Request-Method: POST" "$base/api/events" 2>&1 | Out-String
Check "cors preflight 204" $r "204 No Content"
Check "cors preflight methods" $r "Access-Control-Allow-Methods:"

# 13. QUIT
$null = curl.exe -s -H "X-Pulse-Quit: 1" "$base/health" 2>&1
if (-not $srv.WaitForExit(10000)) {
    Write-Host "smoke: server did not exit after QUIT; killing"
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    $srv.WaitForExit(5000) | Out-Null
}
$srvExit = $srv.ExitCode
$srvLog = $srv.StandardOutput.ReadToEnd() + $srv.StandardError.ReadToEnd()
Set-Content -LiteralPath (Join-Path $logDir "http-smoke.out") -Value $srvLog

Write-Host "--- server output ---"
Write-Host $srvLog.TrimEnd()
Write-Host ("smoke: pass={0} fail={1} server_exit={2}" -f $pass, $fail, $srvExit)

if ($fail -eq 0 -and $srvExit -eq 0) {
    Write-Host "smoke: GREEN"
    exit 0
}
Write-Host "smoke: RED"
exit 1
