#!/usr/bin/env bash
# XIOM PULSE WSL soak client -- independent cross-check of the Windows
# PowerShell soak driver (a PS driver stalled after ~36 min on 2026-10-05
# while the XIOM server stayed responsive; this client provides a second
# data point from WSL2).
#
# Usage: wsl_soak.sh <host> <port> <seconds> <outfile>
set -u
host="$1"; port="$2"; seconds="$3"; out="$4"
start=$(date +%s)
end=$((start + seconds))
ok=0; fail=0; last=$start
echo "$(date -u +%FT%TZ) wsl-soak start host=$host:$port seconds=$seconds" >> "$out"
while [ "$(date +%s)" -lt "$end" ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$host:$port/health" 2>/dev/null)
  if [ "$code" = "200" ]; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  now=$(date +%s)
  if [ $((now - last)) -ge 60 ]; then
    echo "$(date -u +%FT%TZ) elapsed=$((now - start))s ok=$ok fail=$fail" >> "$out"
    last=$now
  fi
  sleep 0.5
done
echo "$(date -u +%FT%TZ) wsl-soak done ok=$ok fail=$fail" >> "$out"
if [ "$fail" -eq 0 ]; then exit 0; fi
exit 1
