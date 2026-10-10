# C-PULSE-18 repro: `time.sleep_ms` is a no-op

**Filed 2026-10-10 by the PULSE lane (routed to compiler/stdlib).**
Toolchain: v0.64.2 -- reproduced on BOTH platforms (Windows lane stdlib
and Linux pinned `4dd8844`).

## Symptom

`time.sleep_ms(500)` returns immediately; `time.monotonic_ms()` deltas
across the call are 0. Consumers that pace loops (retry backoff, harness
writers, rate shaping) turn into busy spins or race past their wait.
PULSE hit it in the ORBITDB hard-kill harness writer (it "timed out" in
milliseconds); the writer now busy-waits on a monotonic deadline.

## Run

```
.\scripts\run.ps1 docs\repro\time-sleep-noop\probe.xi
```

Exit 0 = sleep worked (>=450ms observed); exit 1 = no-op reproduced.
Expect the same shape for `time.sleep(Duration)` if the runtime clock
wait is the root cause.
