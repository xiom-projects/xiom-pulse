# ============================================================================
# XIOM PULSE -- live stream-auth smoke (PULSE_WS_AUTH=jwt).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Starts the product server with PULSE_WS_AUTH=jwt, then checks the upgrade
# path end to end:
#   1. WS handshake without a token        -> 401 + WWW-Authenticate: Bearer
#   2. WS handshake with an invalid token  -> 401
#   3. WS handshake with ?token=<jwt>      -> 101 (Sec-WebSocket-Accept)
#   4. SSE without a token                 -> 401
#   5. SSE with ?token=<jwt>               -> 200 text/event-stream + ticks
#   6. access log redacts the token        -> token=REDACTED, raw token absent
#
# Usage: .\scripts\ws_auth_smoke.ps1 [-Port 18410] [-Secret s3cret]
# Exit: 0 = all checks pass, N = number of failures, 2 = server start failed.
# The run is short (6 requests) but still guarded by a 600 MB RSS watchdog.
# ============================================================================
param(
    [string]$Exe = "",
    [int]$Port = 18410,
    [string]$Secret = "s3cret",
    [int]$MaxMB = 600
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Exe) { $Exe = Join-Path $repoRoot "out\pulse_app.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "ERROR: missing $Exe"; exit 2 }

$token = & python -c @"
import base64, hashlib, hmac, json, time
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
h = b64(json.dumps({'alg':'HS256','typ':'JWT'}, separators=(',',':')).encode())
p = b64(json.dumps({'sub':'smoke','exp':int(time.time())+300}, separators=(',',':')).encode())
s = b64(hmac.new(b'$Secret', (h+'.'+p).encode(), hashlib.sha256).digest())
print(h+'.'+p+'.'+s)
"@
if (-not $token) { Write-Host "ERROR: could not mint a JWT (python)"; exit 2 }
$token = $token.Trim()

$env:PULSE_PORT = "$Port"
$env:PULSE_LOG = "1"
$env:PULSE_WS_AUTH = "jwt"
$env:PULSE_JWT_SECRET = $Secret
$env:PULSE_STORE_PATH = Join-Path $env:TEMP "pulse-wsauth-store.jsonl"
$env:PULSE_AUDIT_PATH = Join-Path $env:TEMP "pulse-wsauth-audit.log"
$env:PULSE_IDLE_TIMEOUT = "2000"
Remove-Item -LiteralPath $env:PULSE_STORE_PATH, $env:PULSE_AUDIT_PATH -ErrorAction SilentlyContinue

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$srv = New-Object System.Diagnostics.Process
$srv.StartInfo = $psi
$null = $srv.Start()
Start-Sleep -Milliseconds 900
if ($srv.HasExited) {
    Write-Host "ERROR: server exited at startup"
    Write-Host ($srv.StandardOutput.ReadToEnd() + $srv.StandardError.ReadToEnd())
    exit 2
}

$fails = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host "[PASS] $name" } else { Write-Host "[FAIL] $name ($detail)"; $script:fails++ }
}
function Get-Ws { try { (Get-Process -Id $srv.Id).WorkingSet64 } catch { 0 } }
$capBytes = [int64]$MaxMB * 1MB

# Send one raw request; return everything the server writes until it closes
# or the read times out (headers enough for 401/101; SSE closes itself).
function Send-Raw([string]$text) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $c.ReceiveTimeout = 2500
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $b = [Text.Encoding]::ASCII.GetBytes($text)
        $s.Write($b, 0, $b.Length)
        $out = New-Object System.Text.StringBuilder
        $buf = New-Object byte[] 8192
        while ($true) {
            try { $n = $s.Read($buf, 0, $buf.Length) } catch { break }
            if ($n -le 0) { break }
            [void]$out.Append([Text.Encoding]::ASCII.GetString($buf, 0, $n))
            if ($out.ToString() -match "\r\n\r\n" -and $text -match "Upgrade: websocket") { break }
        }
        return $out.ToString()
    } finally {
        $c.Close()
        if ((Get-Ws) -gt $capBytes) {
            Write-Warning "ws-auth-smoke: RSS cap exceeded; killing"
            taskkill /T /F /PID $srv.Id 2>$null | Out-Null
        }
    }
}

$key = "dGhlIHNhbXBsZSBub25jZQ=="
$wsNoTok = "GET /api/ws HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: $key`r`nSec-WebSocket-Version: 13`r`n`r`n"
$r1 = Send-Raw $wsNoTok
Check "ws no token 401" ($r1 -match "^HTTP/1\.1 401") ($r1.Split("`r`n")[0])
Check "ws no token challenge" ($r1 -match "(?i)WWW-Authenticate: Bearer") "missing WWW-Authenticate"

$wsBad = "GET /api/ws?token=not-a-jwt HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: $key`r`nSec-WebSocket-Version: 13`r`n`r`n"
$r2 = Send-Raw $wsBad
Check "ws bad token 401" ($r2 -match "^HTTP/1\.1 401") ($r2.Split("`r`n")[0])

$wsOk = "GET /api/ws?token=$token HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: $key`r`nSec-WebSocket-Version: 13`r`n`r`n"
$r3 = Send-Raw $wsOk
Check "ws valid token 101" ($r3 -match "^HTTP/1\.1 101") ($r3.Split("`r`n")[0])
Check "ws accept header" ($r3 -match "(?i)Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK\+xOo=") "missing accept"

$sseNo = "GET /api/sse?events=1&interval_ms=0 HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n"
$r4 = Send-Raw $sseNo
Check "sse no token 401" ($r4 -match "^HTTP/1\.1 401") ($r4.Split("`r`n")[0])

$sseOk = "GET /api/sse?events=1&interval_ms=0&token=$token HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n"
$r5 = Send-Raw $sseOk
Check "sse valid token 200" ($r5 -match "^HTTP/1\.1 200") ($r5.Split("`r`n")[0])
Check "sse content type" ($r5 -match "(?i)Content-Type: text/event-stream") "missing content type"
Check "sse tick" ($r5 -match "event: tick") "missing tick"

# Quit and inspect the access log for redaction.
$quit = "GET / HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nX-Pulse-Quit: 1`r`n`r`n"
$null = Send-Raw $quit
if (-not $srv.WaitForExit(10000)) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
$log = $srv.StandardOutput.ReadToEnd() + $srv.StandardError.ReadToEnd()
Check "log redacts token" ($log -match "token=REDACTED") "no token=REDACTED line"
Check "log lacks raw token" (-not $log.Contains($token)) "raw token appears in the log"

if ($fails -eq 0) { Write-Host "ws-auth-smoke: GREEN (11/11)" } else { Write-Host "ws-auth-smoke: FAILED=$fails" }
exit $fails
