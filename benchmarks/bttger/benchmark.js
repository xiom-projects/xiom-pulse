"use strict"

// XIOM PULSE -- bttger six-endpoint benchmark driver.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adapted from E:\repos\web-framework-benchmarks\benchmark-script\benchmark.js
// (MIT; the reference checkout is never modified). Same contract, same
// autocannon settings by default; the only additions are env knobs, a
// metadata wrapper and a non-2xx/error gate.
//
// Usage: node benchmark.js <title>
// Env: BENCH_PORT (8080), BENCH_HOST (127.0.0.1), BENCH_CONNECTIONS (10),
//      BENCH_AMOUNT (1000000), BENCH_WARMUP (30), BENCH_ONLY (substring).

const fs = require("fs");
const os = require("os");
const path = require("path");
const autocannon = require("autocannon");

const TITLE = process.argv[2] || "xiom-pulse";
const CONNECTIONS = Number(process.env.BENCH_CONNECTIONS || 10);
const AMOUNT = Number(process.env.BENCH_AMOUNT || 1000000);
const WARMUP_DURATION = Number(process.env.BENCH_WARMUP || 30);
const PORT = Number(process.env.BENCH_PORT || 8080);
const HOST = process.env.BENCH_HOST || "127.0.0.1";
const ONLY = process.env.BENCH_ONLY || "";
const BASE = `http://${HOST}:${PORT}`;
const RESULTS_DIR = path.join(__dirname, "results");

const INSERT_BODY = JSON.stringify({
  name: "Sightseeing",
  addresses: [
    { street: "Breite Straße", number: 89, city: "Lübeck" },
    { street: "Breite Straße", number: 89, city: "Lübeck" }
  ],
  oldTown: true
});

const ENDPOINTS = [
  { name: "getSerialized", path: "/serialize" },
  { name: "getSerializedBig", path: "/serialize/big" },
  { name: "getPlainText", path: "/plain/text" },
  {
    name: "getQueryResult",
    path: "/query/300/tools/10?model=Dozer&factor=ATX&length=800&width=800&allow=true",
    headers: { "x-api-key": "zb478fb3", "x-session-id": "jhg723bf" }
  },
  {
    name: "insertObject",
    path: "/insert",
    method: "POST",
    headers: { "content-type": "application/json" },
    body: INSERT_BODY
  },
  { name: "getCalculated", path: "/calculate", amount: Math.max(1, Math.floor(AMOUNT / 100)) }
];

function selected() {
  if (!ONLY) return ENDPOINTS;
  return ENDPOINTS.filter((e) => e.name.includes(ONLY));
}

async function runOne(ep) {
  const amount = ep.amount || AMOUNT;
  const started = Date.now();
  const opts = {
    title: `${TITLE} - ${ep.name}`,
    url: BASE + ep.path,
    connections: CONNECTIONS,
    amount
  };
  if (ep.method) opts.method = ep.method;
  if (ep.headers) opts.headers = ep.headers;
  if (ep.body) opts.body = ep.body;
  const result = await autocannon(opts);
  const elapsed = ((Date.now() - started) / 1000).toFixed(1);
  console.log(
    `${ep.name}: ${result.requests.average.toFixed(0)} req/s ` +
    `p50=${result.latency.p50}ms p99=${result.latency.p99}ms ` +
    `2xx=${result["2xx"]} non2xx=${result.non2xx} errors=${result.errors} ` +
    `(${elapsed}s)`
  );
  return { name: ep.name, amount, result };
}

async function main() {
  if (!fs.existsSync(RESULTS_DIR)) fs.mkdirSync(RESULTS_DIR, { recursive: true });
  if (WARMUP_DURATION > 0) {
    console.log(`warmup: ${WARMUP_DURATION}s on /serialize`);
    await autocannon({
      title: `${TITLE} - warmup`,
      url: BASE + "/serialize",
      connections: CONNECTIONS,
      duration: WARMUP_DURATION
    });
  }
  const results = [];
  for (const ep of selected()) {
    results.push(await runOne(ep));
  }
  const payload = {
    title: TITLE,
    generatedAt: new Date().toISOString(),
    host: os.hostname(),
    platform: process.platform,
    release: os.release(),
    cpus: os.cpus().length,
    node: process.version,
    autocannon: require("autocannon/package.json").version,
    port: PORT,
    connections: CONNECTIONS,
    amount: AMOUNT,
    warmupSeconds: WARMUP_DURATION,
    results
  };
  const out = path.join(RESULTS_DIR, `${TITLE}.json`);
  fs.writeFileSync(out, JSON.stringify(payload, null, 2));
  const bad = results.filter((r) => r.result.non2xx > 0 || r.result.errors > 0);
  console.log(`wrote ${out}`);
  if (bad.length > 0) {
    console.error(`FAILED: non-2xx or errors on ${bad.map((b) => b.name).join(", ")}`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
