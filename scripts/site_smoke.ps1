#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- dynamic site scaffold smoke.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds examples/site/main.xi, starts it on a local port, and checks the
# server-rendered pages, the urlencoded form (success + validation), assets,
# the custom 404 and the traversal guard. Exit code = failures (0 = green).
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18095
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$fail = 0

function Expect([string]$Name, [bool]$Ok) {
    if ($Ok) {
        Write-Host "[PASS] $Name"
    } else {
        Write-Host "[FAIL] $Name"
        $script:fail = $script:fail + 1
    }
}

function Web-Get([string]$Path) {
    $raw = & curl.exe -s -o - -w "`n@@STATUS@@%{http_code}" "http://127.0.0.1:$Port$Path"
    $text = ($raw -join "`n")
    $idx = $text.LastIndexOf("@@STATUS@@")
    return @{ status = [int]$text.Substring($idx + 10); body = $text.Substring(0, $idx) }
}

function Web-Post([string]$Path, [string]$ContentType, [string]$Data) {
    $raw = & curl.exe -s -o - -w "`n@@STATUS@@%{http_code}" -X POST -H "Content-Type: $ContentType" --data $Data "http://127.0.0.1:$Port$Path"
    $text = ($raw -join "`n")
    $idx = $text.LastIndexOf("@@STATUS@@")
    return @{ status = [int]$text.Substring($idx + 10); body = $text.Substring(0, $idx) }
}

function Web-Head([string]$Path) {
    $raw = & curl.exe -s -o NUL -w "%{http_code} %{content_type}" "http://127.0.0.1:$Port$Path"
    return $raw
}

function Web-HeadRaw([string]$Path) {
    # --path-as-is keeps a literal ../ in the request target so the static
    # engine's traversal guard is exercised (curl normalises it otherwise).
    $raw = & curl.exe --path-as-is -s -o NUL -w "%{http_code} %{content_type}" "http://127.0.0.1:$Port$Path"
    return $raw
}

& (Join-Path $PSScriptRoot "build.ps1") "examples/site/main.xi" -Name site_example -TimeoutSec 300 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "site example build failed" }

$env:PULSE_PORT = "$Port"
$env:PULSE_LOG = "0"
$env:SITE_ROOT = "examples/site"
$proc = Start-Process -FilePath (Join-Path $repoRoot "out/site_example.exe") -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden

try {
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $h = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2 -ErrorAction Stop
            if ($h.StatusCode -eq 200) { $ready = $true; break }
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $ready) { throw "site server did not become ready on port $Port" }

    $homePage = Web-Get "/"
    Expect "home 200" ($homePage.status -eq 200)
    Expect "home layout" ($homePage.body.Contains("PULSE site example") -and $homePage.body.Contains("class=`"bar`"") -and $homePage.body.Contains("class=`"foot`""))

    $about = Web-Get "/about"
    Expect "about 200" ($about.status -eq 200 -and $about.body.Contains("About this site"))

    $features = Web-Get "/features"
    Expect "features loop" ($features.status -eq 200 -and $features.body.Contains("application/x-www-form-urlencoded form parsing"))

    $contact = Web-Get "/contact"
    Expect "contact form" ($contact.status -eq 200 -and $contact.body.Contains("<form method=`"post`" action=`"/contact`">"))

    $ok = Web-Post "/contact" "application/x-www-form-urlencoded" "name=Ada+Lovelace&message=Hello+%26+welcome%21+%3Cb%3E"
    Expect "form success 200" ($ok.status -eq 200)
    Expect "form reflected name" ($ok.body.Contains("Thanks, Ada Lovelace."))
    Expect "form escaped value" ($ok.body.Contains("Hello &amp; welcome! &lt;b&gt;"))

    $bad = Web-Post "/contact" "application/x-www-form-urlencoded" "message=only"
    Expect "form validation 400" ($bad.status -eq 400 -and $bad.body.Contains("Name is required."))

    $wrong = Web-Post "/contact" "application/json" "{}"
    Expect "form wrong content-type 415" ($wrong.status -eq 415)

    $css = Web-Head "/assets/style.css"
    Expect "asset css 200 text/css" ($css -eq "200 text/css")

    $missing = Web-Get "/nope"
    Expect "custom 404" ($missing.status -eq 404 -and $missing.body.Contains("Page not found") -and $missing.body.Contains("/nope"))

    $trav = Web-HeadRaw "/assets/../main.xi"
    Expect "asset traversal blocked" (-not $trav.StartsWith("200"))

    if ($fail -eq 0) {
        Write-Host "site-smoke: GREEN"
        exit 0
    }
    Write-Host "site-smoke: RED failures=$fail"
    exit 1
} finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
