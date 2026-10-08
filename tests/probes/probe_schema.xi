// probe_schema -- JSON body schema validator (src/schema.xi).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: scripts/run.sh tests\probes\probe_schema.xi
// Exit code = failures (0 = green).
module pulse_probe_schema

use xiom.io;
use xiom.pulse.schema;

pub fn main() -> Int {
  var fails: Int = 0;

  var rules = schema.schema_rules_new();
  schema.schema_string(&mut rules, "user", true, 1, 8);
  schema.schema_number(&mut rules, "n", false, 0, 100);
  schema.schema_bool(&mut rules, "flag", false);

  // 1. valid body (all fields, optional included).
  let r1 = schema.schema_validate(&rules, "{\"user\":\"carol\",\"n\":5,\"flag\":true}");
  if !r1.ok {
    io.println("[FAIL] valid body: " + r1.code + " " + r1.message);
    fails = fails + 1;
  } else {
    io.println("[PASS] valid body");
  }

  // 2. missing required field.
  let r2 = schema.schema_validate(&rules, "{\"n\":1}");
  if r2.ok || r2.code != "missing" || r2.field != "user" {
    io.println("[FAIL] missing required");
    fails = fails + 1;
  } else {
    io.println("[PASS] missing required");
  }

  // 3. wrong type.
  let r3 = schema.schema_validate(&rules, "{\"user\":42}");
  if r3.ok || r3.code != "type" || r3.field != "user" {
    io.println("[FAIL] wrong type");
    fails = fails + 1;
  } else {
    io.println("[PASS] wrong type");
  }

  // 4. max length.
  let r4 = schema.schema_validate(&rules, "{\"user\":\"aaaaaaaaa\"}");
  if r4.ok || r4.code != "max" {
    io.println("[FAIL] max length");
    fails = fails + 1;
  } else {
    io.println("[PASS] max length");
  }

  // 5. min length (empty string).
  let r5 = schema.schema_validate(&rules, "{\"user\":\"\"}");
  if r5.ok || r5.code != "min" {
    io.println("[FAIL] min length");
    fails = fails + 1;
  } else {
    io.println("[PASS] min length");
  }

  // 6. number below minimum.
  let r6 = schema.schema_validate(&rules, "{\"user\":\"a\",\"n\":-1}");
  if r6.ok || r6.code != "min" || r6.field != "n" {
    io.println("[FAIL] number min");
    fails = fails + 1;
  } else {
    io.println("[PASS] number min");
  }

  // 7. number above maximum.
  let r7 = schema.schema_validate(&rules, "{\"user\":\"a\",\"n\":101}");
  if r7.ok || r7.code != "max" || r7.field != "n" {
    io.println("[FAIL] number max");
    fails = fails + 1;
  } else {
    io.println("[PASS] number max");
  }

  // 8. number wrong type.
  let r8 = schema.schema_validate(&rules, "{\"user\":\"a\",\"n\":\"x\"}");
  if r8.ok || r8.code != "type" {
    io.println("[FAIL] number type");
    fails = fails + 1;
  } else {
    io.println("[PASS] number type");
  }

  // 9. non-object body.
  let r9 = schema.schema_validate(&rules, "[1,2]");
  if r9.ok || r9.code != "not_object" {
    io.println("[FAIL] not object");
    fails = fails + 1;
  } else {
    io.println("[PASS] not object");
  }

  // 10. invalid JSON.
  let r10 = schema.schema_validate(&rules, "notjson");
  if r10.ok || r10.code != "invalid_json" {
    io.println("[FAIL] invalid json");
    fails = fails + 1;
  } else {
    io.println("[PASS] invalid json");
  }

  // 11. optional fields may be absent.
  let r11 = schema.schema_validate(&rules, "{\"user\":\"a\"}");
  if !r11.ok {
    io.println("[FAIL] optional absent");
    fails = fails + 1;
  } else {
    io.println("[PASS] optional absent");
  }

  // 12. bool wrong type.
  let r12 = schema.schema_validate(&rules, "{\"user\":\"a\",\"flag\":\"x\"}");
  if r12.ok || r12.code != "type" || r12.field != "flag" {
    io.println("[FAIL] bool type");
    fails = fails + 1;
  } else {
    io.println("[PASS] bool type");
  }

  // 13. string extraction.
  let v1 = schema.schema_str_value("{\"user\":\"bob\"}", "user");
  let v2 = schema.schema_str_value("{\"n\":1}", "user");
  let v3 = schema.schema_str_value("notjson", "user");
  if v1 != "bob" || v2 != "" || v3 != "" {
    io.println("[FAIL] str value extraction");
    fails = fails + 1;
  } else {
    io.println("[PASS] str value extraction");
  }

  if fails == 0 {
    io.println("[PASS] schema");
    return 0;
  }
  io.println("[FAIL] schema fails=" + fails.to_str());
  return fails;
}
