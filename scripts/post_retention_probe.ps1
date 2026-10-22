# ============================================================================
# XIOM PULSE -- HTTP request/response retention probe (Windows).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Diagnostic for the bttger `/insert` growth (m375/PULSE): drives one server
# over a fixed number of keep-alive requests, samples WorkingSet64 after each
# batch, and reports the steady-state bytes/request. A hard RSS watchdog
# kills the tree at -MaxMB (exit 137) so a leak cannot take the workstation.
#
# Usage:
#   .\scripts\post_retention_probe.ps1 -Method POST -Path /insert -BodyFile body.json
#   .\scripts\post_retention_probe.ps1 -Method GET  -Path /serialize
#   .\scripts\post_retention_probe.ps1 -Method POST -Path /insert -Body "{}"
# Exit: 0 = ran cleanly (growth is informational), 1 = request failures,
#       137 = RSS cap exceeded, 2 = bad input / server did not start.
# ============================================================================
param(
    [string]$Exe = "",
    [int]$Port = 18190,
    [ValidateSet("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD")]
    [string]$Method = "POST",
    [string]$Path = "/insert",
    [string]$Body = "",
    [string]$BodyFile = "",
    [int]$Requests = 1500,
    [int]$Batch = 100,
    [int]$Connections = 1,
    [int]$RecycleEvery = 0,
    [int]$MaxMB = 600,
    [int]$TimeoutSec = 20,
    [string]$ContentType = "application/json",
    [switch]$Close,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 does not auto-load the HTTP client assembly.
Add-Type -AssemblyName System.Net.Http
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Exe) { $Exe = Join-Path $repoRoot "out\bench_bttger.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "ERROR: missing $Exe"; exit 2 }
if ($BodyFile) {
    if (-not (Test-Path -LiteralPath $BodyFile)) { Write-Host "ERROR: missing $BodyFile"; exit 2 }
    $Body = Get-Content -LiteralPath $BodyFile -Raw
}
if ($MaxMB -lt 64) { Write-Host "ERROR: MaxMB must be >= 64"; exit 2 }
if ($Requests -lt 1 -or $Batch -lt 1) { Write-Host "ERROR: Requests/Batch must be >= 1"; exit 2 }

$env:PULSE_PORT = "$Port"
$env:PULSE_LOG = "0"
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
    Write-Host "ERROR: server exited at startup (code $($srv.ExitCode))"
    Write-Host ($srv.StandardOutput.ReadToEnd() + $srv.StandardError.ReadToEnd())
    exit 2
}

function Get-Ws { param($Proc) try { (Get-Process -Id $Proc.Id).WorkingSet64 } catch { 0 } }

$capBytes = [int64]$MaxMB * 1MB
function New-Client {
    $h = New-Object System.Net.Http.HttpClientHandler
    $h.MaxConnectionsPerServer = $Connections
    $h.AllowAutoRedirect = $false
    $c = New-Object System.Net.Http.HttpClient($h)
    $c.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    return $c
}
$client = New-Client
$uri = "http://127.0.0.1:$Port$Path"

$ws0 = Get-Ws $srv
if (-not $Quiet) {
    Write-Host ("post-retention: {0} {1} body={2}B requests={3} batch={4} conns={5} recycle={6} cap={7}MB ws0={8}" -f `
        $Method, $Path, $Body.Length, $Requests, $Batch, $Connections, $RecycleEvery, $MaxMB, $ws0)
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ok = 0
$fail = 0
$lastCode = 0
$samples = New-Object System.Collections.ArrayList
$capped = $false
while ($ok + $fail -lt $Requests) {
    if ($RecycleEvery -gt 0 -and ($ok + $fail) -gt 0 -and (($ok + $fail) % $RecycleEvery) -eq 0) {
        $client.Dispose()
        $client = New-Client
    }
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::new($Method), $uri)
    if ($Close) { $req.Headers.ConnectionClose = $true }
    if ($Body.Length -gt 0 -and $Method -ne "GET" -and $Method -ne "HEAD") {
        $req.Content = New-Object System.Net.Http.StringContent($Body, [Text.Encoding]::UTF8, $ContentType)
    }
    try {
        $resp = $client.SendAsync($req).Result
        $lastCode = [int]$resp.StatusCode
        $null = $resp.Content.ReadAsStringAsync().Result
        $resp.Dispose()
        $ok++
    } catch {
        $fail++
        if ($fail -ge 20 -and $ok -eq 0) { break }
    }
    if (($ok + $fail) % $Batch -eq 0) {
        $ws = Get-Ws $srv
        [void]$samples.Add([pscustomobject]@{ n = $ok + $fail; ws = $ws; status = $lastCode })
        if (-not $Quiet) {
            Write-Host ("  n={0} ok={1} fail={2} status={3} ws={4:N0}KB" -f ($ok + $fail), $ok, $fail, $lastCode, ($ws / 1KB))
        }
        if ($ws -gt $capBytes) {
            Write-Warning ("post-retention: RSS {0:N0}MB > {1}MB cap; killing PID {2}" -f ($ws / 1MB), $MaxMB, $srv.Id)
            & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
            $capped = $true
            break
        }
    }
}
$sw.Stop()

$wsEnd = if ($capped) { $capBytes } else { Get-Ws $srv }
$n = $ok + $fail
$steady = 0.0
if ($samples.Count -ge 3) {
    $a = $samples[1]
    $dn = $samples[$samples.Count - 1].n - $a.n
    $dw = $samples[$samples.Count - 1].ws - $a.ws
    if ($dn -gt 0) { $steady = [math]::Round($dw / $dn, 2) }
}
$perAll = if ($n -gt 0) { [math]::Round(($wsEnd - $ws0) / $n, 2) } else { 0 }
$summary = ("post-retention summary: {0} {1} n={2} ok={3} fail={4} last={5} ws0={6} wsend={7} growth={8} bytes/req(all)={9} bytes/req(steady)={10} capped={11} elapsed_ms={12}" -f `
    $Method, $Path, $n, $ok, $fail, $lastCode, $ws0, $wsEnd, ($wsEnd - $ws0), $perAll, $steady, $capped, [int]$sw.Elapsed.TotalMilliseconds)
Write-Host $summary

if ($capped) {
    if (-not $srv.HasExited) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
    exit 137
}
if (-not $srv.HasExited) {
    try {
        $q = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "http://127.0.0.1:$Port/")
        $q.Headers.Add("X-Pulse-Quit", "1")
        $null = $client.SendAsync($q).Result
    } catch { }
    if (-not $srv.WaitForExit(10000)) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
}
$client.Dispose()
if ($fail -gt 0) { exit 1 }
exit 0
