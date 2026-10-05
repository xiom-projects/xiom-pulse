// XIOM PULSE -- project manifest.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// PULSE is an EXTERNAL PROJECT (see stdlib docs/STDLIB_EXTENSION.md S9):
// the official XIOM full web backend. It is not published to the package
// registry; the manifest exists so the compiler resolves in-tree modules
// and so project deps are explicit.
package xiom_pulse {
  name: "xiom.pulse";
  version: "0.1.0";
  description: "XIOM PULSE -- full web backend (external project lane)";
  categories: ["web", "network"];
  keywords: ["http", "server", "backend", "web"];
  license: "MIT OR Apache-2.0";
  authors: ["Lefteris Notas"];
  modules: ["xiom.pulse", "xiom.pulse.http", "xiom.pulse.router", "xiom.pulse.envelope", "xiom.pulse.config", "xiom.pulse.metrics", "xiom.pulse.session", "xiom.pulse.store", "xiom.pulse.ratelimit", "xiom.pulse.server"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0", "xiom.http": "0.1.1", "xiom.cookie": "0.1.1", "xiom.jwt": "0.2.0", "xiom.router": "0.1.0", "xiom.rate": "0.2.0" };
}
