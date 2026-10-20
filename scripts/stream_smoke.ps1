# XIOM PULSE -- live SSE + WebSocket smoke (Windows wrapper).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Starts the product server, runs scripts/stream_smoke.py against it, then
# quits the server with X-Pulse-Quit. The raw client checks live in Python
# so the Windows and Linux wrappers share one protocol implementation.
param(
    [int]$Port = 18097,
    [string]$ServerExe = ".\out\pulse_app.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$srvExe = Join-Path $repoRoot $ServerExe
if (-not (Test-Path -LiteralPath $srvExe)) {
    Write-Error "server binary not found: $srvExe"
    exit 1
}
$logDir = Join-Path $repoRoot "probe-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$srvLog = Join-Path $logDir "stream-smoke-server-$stamp.log"

$env:PULSE_PORT = "$Port"
$env:PULSE_RATE_LIMIT = "0"
$env:PULSE_RATE_ROUTES = ""
# Deterministic Origin policy for the bad-origin check (http_smoke runs
# earlier in the same CI shell and leaves PULSE_CORS_ORIGIN=* behind).
$env:PULSE_CORS_ORIGIN = ""
if (-not $env:PULSE_MAX_RSS_MB) { $env:PULSE_MAX_RSS_MB = "2048" }

# Owner directive: launch the app under the RSS watchdog.
$capScript = Join-Path $repoRoot "scripts\capped_app.ps1"
$capArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $capScript, "-Exe", $srvExe)
$srvErrLog = "$srvLog.err"
$srv = Start-Process -FilePath "powershell" -ArgumentList $capArgs -PassThru -NoNewWindow -RedirectStandardOutput $srvLog -RedirectStandardError $srvErrLog

$ready = $false
for ($i = 0; $i -lt 50; $i++) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        $c.Close()
        $ready = $true
        break
    } catch {
        Start-Sleep -Milliseconds 200
    }
}
if (-not $ready) {
    if (Test-Path -LiteralPath $srvLog) { Get-Content -LiteralPath $srvLog }
    Write-Error "server did not listen on 127.0.0.1:$Port"
    exit 1
}

$py = "python"
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { $py = "py" }
$check = & $py (Join-Path $repoRoot "scripts\stream_smoke.py") --port $Port 2>&1
$rc = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }

# Quit (the stream check owns no connection now); fall back to TERM.
try {
    $q = New-Object System.Net.Sockets.TcpClient
    $q.Connect("127.0.0.1", $Port)
    $qs = $q.GetStream()
    $qb = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nX-Pulse-Quit: 1`r`n`r`n")
    $qs.Write($qb, 0, $qb.Length)
    $q.Close()
} catch { }
if (-not $srv.WaitForExit(10000)) {
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    $srv.WaitForExit(5000) | Out-Null
}
if ($rc -ne 0 -and (Test-Path -LiteralPath $srvLog)) {
    Write-Host "---- server log ----"
    Get-Content -LiteralPath $srvLog | Select-Object -Last 20
    Write-Host "--------------------"
}
exit $rc
