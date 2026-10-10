---
title: Install
description: Download and verify a PULSE release artifact.
---

# Install

PULSE ships as a single binary archive per platform. There is no
installer and no runtime dependency beyond the C library the binary was
built against (glibc 2.35+ on Linux).

## Downloads

The canonical mirror is `dl.xiom-lang.org`; the GitHub release page
carries the same files.

```
https://dl.xiom-lang.org/pulse/releases/pulse-v0.2.0/pulse-0.2.0-linux-x64.zip
https://dl.xiom-lang.org/pulse/releases/pulse-v0.2.0/pulse-0.2.0-windows-x64.zip
```

Substitute the tag reported by
`https://dl.xiom-lang.org/pulse/latest.json` for your platform -- the
examples below use `0.2.0`, the current release.

Each archive contains `pulse_app` (Linux) or `pulse_app.exe` (Windows),
`resources/img/pulse-ico.ico`, `README.md`, `LICENSE-MIT`,
`LICENSE-APACHE` and `NOTICE`. Every release also ships per-asset
`.sha256` files and a combined `SHA256SUMS`.

## Verify

Linux:

```bash
curl -LO https://dl.xiom-lang.org/pulse/releases/pulse-v0.2.0/pulse-0.2.0-linux-x64.zip
curl -LO https://dl.xiom-lang.org/pulse/releases/pulse-v0.2.0/SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
unzip pulse-0.2.0-linux-x64.zip -d pulse-0.2.0
./pulse-0.2.0/pulse_app --version
```

Windows (PowerShell):

```powershell
Invoke-WebRequest -Uri "https://dl.xiom-lang.org/pulse/releases/pulse-v0.2.0/pulse-0.2.0-windows-x64.zip" -OutFile pulse.zip
Invoke-WebRequest -Uri "https://dl.xiom-lang.org/pulse/releases/pulse-v0.2.0/SHA256SUMS" -OutFile SHA256SUMS
# compare the listed hash with (Get-FileHash pulse.zip -Algorithm SHA256).Hash
Expand-Archive pulse.zip -DestinationPath pulse-0.2.0
.\pulse-0.2.0\pulse_app.exe --version
```

`latest.json` at `https://dl.xiom-lang.org/pulse/latest.json` names the
current tag and its assets.

## Platforms

Linux x64 and Windows x64 are tested and shipped. macOS is not published
yet (no artifact, no download button anywhere). Builds are cut from the
release workflow only when the platform suite is green; see the
[Release history](./releases.md).
