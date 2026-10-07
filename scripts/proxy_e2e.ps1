#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE through-proxy E2E: nginx terminates TLS (self-signed) and
# proxies to PULSE on loopback; verify health, POST bodies, metrics and
# security headers over HTTPS.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\proxy_e2e.ps1
# Exit code: 0 = green, 1 = failed. Artifacts under probe-logs\proxy-e2e\.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18091,
    [int]$ProxyPort = 8443,
    [string]$NginxPath = "C:\Users\lefte\Downloads\nginx-1.28.3\nginx-1.28.3",
    [string]$ServerExe = "",
    [string]$OpenSsl = "C:\Program Files\Git\usr\bin\openssl.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app_v9.exe" }
$nginxExe = Join-Path $NginxPath "nginx.exe"
if (-not (Test-Path -LiteralPath $nginxExe)) { throw "nginx not found at $nginxExe" }
if (-not (Test-Path -LiteralPath $OpenSsl)) { throw "openssl not found at $OpenSsl" }

$work = Join-Path $repoRoot "probe-logs\proxy-e2e"
$confDir = Join-Path $work "conf"
$certDir = Join-Path $work "cert"
$logsDir = Join-Path $work "logs"
$tempRoot = Join-Path $work "temp"
foreach ($d in @($work, $confDir, $certDir, $logsDir, $tempRoot,
                 (Join-Path $tempRoot "client_body_temp"), (Join-Path $tempRoot "proxy_temp"),
                 (Join-Path $tempRoot "fastcgi_temp"), (Join-Path $tempRoot "uwsgi_temp"),
                 (Join-Path $tempRoot "scgi_temp"))) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# --- self-signed cert -------------------------------------------------------
$crt = Join-Path $certDir "pulse.crt"
$key = Join-Path $certDir "pulse.key"
if (-not (Test-Path -LiteralPath $crt) -or -not (Test-Path -LiteralPath $key)) {
    # openssl writes progress dots to stderr; PS 5.1 + Stop would abort on them.
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $OpenSsl req -x509 -newkey rsa:2048 -nodes -keyout $key -out $crt -days 2 `
        -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>&1 | Out-Null
    $ErrorActionPreference = $savedEap
    if (-not (Test-Path -LiteralPath $crt)) { throw "cert generation failed" }
}
Write-Host "proxy-e2e: cert ready ($crt)"

# --- nginx config -----------------------------------------------------------
# Absolute forward-slash paths: nginx resolves relative paths against the
# config file's directory for certificates, which is not the prefix.
$workFwd = $work -replace '\\', '/'
$crtFwd = $crt -replace '\\', '/'
$keyFwd = $key -replace '\\', '/'
$conf = @"
worker_processes 1;
error_log $workFwd/logs/error.log;
pid $workFwd/logs/nginx.pid;
events { worker_connections 64; }
http {
    access_log $workFwd/logs/access.log;
    server {
        listen 127.0.0.1:$ProxyPort ssl;
        server_name localhost;
        ssl_certificate $crtFwd;
        ssl_certificate_key $keyFwd;
        add_header Strict-Transport-Security "max-age=31536000" always;
        server_tokens off;
        location / {
            proxy_pass http://127.0.0.1:$Port;
            proxy_http_version 1.1;
            proxy_set_header Connection close;
            proxy_set_header X-Forwarded-For `$remote_addr;
            proxy_read_timeout 10s;
            proxy_send_timeout 10s;
        }
        location /metrics {
            allow 127.0.0.1;
            deny all;
            proxy_pass http://127.0.0.1:$Port;
        }
    }
}
"@
Set-Content -LiteralPath (Join-Path $confDir "nginx.conf") -Value $conf

# --- start PULSE ------------------------------------------------------------
$env:PULSE_PORT = "$Port"
$pulseLog = Join-Path $work "pulse-server.out"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"`"$ServerExe`" > `"$pulseLog`" 2>&1`""
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$pulse = New-Object System.Diagnostics.Process
$pulse.StartInfo = $psi
$null = $pulse.Start()
Start-Sleep -Milliseconds 900

# --- start nginx (detached, file-redirected) --------------------------------
# CRITICAL: never let nginx inherit this process's stdout/stderr pipes --
# on Windows the master keeps them open and a pipe-reading caller waits
# forever. Start-Process with file redirection detaches cleanly.
$nginxOut = Join-Path $work "nginx-stdout.out"
$nginxErr = Join-Path $work "nginx-stderr.out"
Remove-Item -LiteralPath $nginxOut, $nginxErr -ErrorAction SilentlyContinue
$ng = Start-Process -FilePath $nginxExe -ArgumentList @("-p", $work, "-c", "conf/nginx.conf") `
    -PassThru -RedirectStandardOutput $nginxOut -RedirectStandardError $nginxErr -WindowStyle Hidden
Start-Sleep -Milliseconds 700

function Test-Port([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect("127.0.0.1", $p, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500)
        if (-not $ok) { $c.Close(); return $false }
        $c.EndConnect($iar)
        $connected = $c.Connected
        $c.Close()
        return $connected
    } catch { return $false }
}
$up = $false
for ($i = 0; $i -lt 5 -and -not $up; $i++) {
    $up = Test-Port $ProxyPort
    if (-not $up) { Start-Sleep -Milliseconds 300 }
}
if (-not $up) {
    Write-Host "proxy-e2e: nginx did not start; error log:"
    Get-Content (Join-Path $logsDir "error.log") -ErrorAction SilentlyContinue | Select-Object -Last 10
    Write-Host "proxy-e2e: stderr:"
    Get-Content $nginxErr -ErrorAction SilentlyContinue | Select-Object -Last 10
    if ($ng -and -not $ng.HasExited) { & taskkill /T /F /PID $ng.Id 2>$null | Out-Null }
    & taskkill /T /F /PID $pulse.Id 2>$null | Out-Null
    exit 1
}
Write-Host "proxy-e2e: nginx listening on 127.0.0.1:$ProxyPort -> $Port"

$base = "https://127.0.0.1:$ProxyPort"
$pass = 0; $fail = 0
function Check {
    param([string]$Name, [string]$Haystack, [string]$Needle, [bool]$Want = $true)
    $has = $Haystack -like "*$Needle*"
    if ($has -eq $Want) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name (want '$Needle')"; Write-Host "----"; Write-Host $Haystack; Write-Host "----"; $script:fail++ }
}

# --- checks over TLS --------------------------------------------------------
$r = curl.exe -sk -i --max-time 8 "$base/health" 2>&1 | Out-String
Check "tls health 200" $r "200 OK"
Check "tls health body" $r '{"status":"ok"}'
Check "hsts header" $r "Strict-Transport-Security"
Check "proxy server header" $r "Server: nginx"
Check "no upstream server leak" $r "xiom-pulse" $false

$bodyFile = Join-Path $env:TEMP ("pulse-proxy-" + [guid]::NewGuid().ToString("N") + ".json")
Set-Content -LiteralPath $bodyFile -Value '{"via":"nginx"}' -NoNewline
try {
    $r = curl.exe -sk -i --max-time 8 -X POST -H "Content-Type: application/json" --data-binary "@$bodyFile" "$base/api/echo" 2>&1 | Out-String
} finally { Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue }
Check "tls post 200" $r "200 OK"
Check "tls post echo" $r '{"echo":{"via":"nginx"}}'

$r = curl.exe -sk -i --max-time 8 "$base/metrics" 2>&1 | Out-String
Check "tls metrics 200" $r "200 OK"
Check "tls metrics text" $r "pulse_http_requests_total"

$r = curl.exe -sk -i --max-time 8 "$base/nope" 2>&1 | Out-String
Check "tls 404" $r "404 Not Found"
Check "tls 404 rid" $r '"rid":"r-'

# upstream log should show the proxied requests (X-Forwarded-For presence
# is upstream-side; PULSE does not record the peer yet -- documented).

# --- stop -------------------------------------------------------------------
if ($ng -and -not $ng.HasExited) {
    & taskkill /T /F /PID $ng.Id 2>$null | Out-Null
    Start-Sleep -Milliseconds 300
}

$c = New-Object System.Net.Sockets.TcpClient
$c.Connect("127.0.0.1", $Port)
$s = $c.GetStream()
$q = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nX-Pulse-Quit: 1`r`n`r`n")
$s.Write($q, 0, $q.Length)
$c.Close()
if (-not $pulse.WaitForExit(15000)) {
    & taskkill /T /F /PID $pulse.Id 2>$null | Out-Null
    $pulse.WaitForExit(5000) | Out-Null
}
$pulseExit = $pulse.ExitCode
$pulseOut = Get-Content -LiteralPath $pulseLog -Raw -ErrorAction SilentlyContinue

Write-Host "--- pulse log tail ---"
$pulseOut.Split("`n") | Select-Object -Last 4 | ForEach-Object { Write-Host $_ }
Write-Host ("proxy-e2e: pass={0} fail={1} pulse_exit={2}" -f $pass, $fail, $pulseExit)

if ($fail -eq 0 -and $pulseExit -eq 0) { Write-Host "proxy-e2e: GREEN"; exit 0 }
Write-Host "proxy-e2e: RED"
exit 1
