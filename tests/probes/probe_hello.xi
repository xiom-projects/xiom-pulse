// probe_hello -- Step 0b baseline: pinned toolchain smoke test.
// Run: .\scripts\run.ps1 tests\probes\probe_hello.xi
// Expected: "pulse hello" on stdout, exit 0.
use xiom.io;

fn main() -> Int {
  io.println("pulse hello");
  return 0;
}
