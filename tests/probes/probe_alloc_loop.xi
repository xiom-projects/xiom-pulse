// probe_alloc_loop -- XIOM runtime allocation stability: churns Vec[UInt8]
// buffers for PROBE_ROUNDS rounds (500 x 64 KiB each). The runner samples
// /proc/<pid>/status externally and reports PEAK RSS: if peak scales with
// total churn the runtime retains freed memory per allocation (leak-class,
// the 30m HTTP soak grows ~48 KB/request linearly); if peak plateaus the
// allocator just keeps a high-water mark.
// Run: PROBE_ROUNDS=16 bash <sampler> (Linux; /proc files stat size 0 so
// in-process sampling via io.read_file* contract-trips).
module probe_alloc_loop

use xiom.io;
use xiom.env;
use xiom.convert.parse;

/// churn allocates `count` fresh buffers of `size` bytes, uses them, and
/// drops them; returns an accumulator so nothing can be elided.
fn churn(count: Int, size: Int) -> Int {
  var acc: Int = 0;
  var i: Int = 0;
  while i < count {
    var b: Vec[UInt8] = Vec[UInt8].new();
    var j: Int = 0;
    while j < size {
      b.push(1u8);
      j = j + 1;
    }
    acc = acc + b.len();
    i = i + 1;
  }
  return acc;
}

pub fn main() -> Int {
  var rounds: Int = 2;
  let pr = parse_int(env.var_or("PROBE_ROUNDS", "2"));
  if pr.is_ok { rounds = pr.value; }
  io.println("alloc-probe start rounds=" + rounds.to_str());
  var total: Int = 0;
  var r: Int = 0;
  while r < rounds {
    total = total + churn(500, 65536);
    r = r + 1;
  }
  io.println("alloc-probe done total=" + total.to_str());
  if total < 0 { return 1; }
  return 0;
}
