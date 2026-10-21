#!/usr/bin/env node
// The gz shim's whole-file-or-nothing law, proven on the exact script
// bytes the built page carries:
//   1. a good .gz hands the engine the WHOLE decompressed file
//   2. a truncated .gz (a link that dropped mid-download) rejects
//      cleanly and falls back to the raw wasm -- no unhandled promise
//   3. a missing .gz (404) falls back to the raw wasm
//   4. a non-wasm URL passes through untouched
//   5. the raw fallback is also whole (and a 404 there rejects, so the
//      engine's own retry takes over)
const fs = require("fs");
const zlib = require("zlib");
const path = require("path").join(__dirname, "..", "builds", "web", "index.html");
const html = fs.readFileSync(path, "utf8");

const m = html.match(/<script>(\/\*qt-wasm-gz\*\/.*?)<\/script>/s);
if (!m) { console.error("FAIL: qt-wasm-gz script not found in built page"); process.exit(1); }
const script = m[1];

// -- the page's world, as far as the shim sees it ------------------------
const calls = [];
function record(url) { calls.push(url); }
const payload = Buffer.alloc(64 * 1024, 7);
for (let i = 0; i < payload.length; i++) payload[i] = (i * 31 + 17) & 0xff;
const goodGz = zlib.gzipSync(payload);
const truncatedGz = goodGz.subarray(0, Math.floor(goodGz.length * 0.6));

let gzMode = "good"; // good | truncated | 404
let rawMode = "good"; // good | 404
globalThis.window = {
  fetch: function (input, init) {
    const url = typeof input === "string" ? input : input.url;
    record(url);
    if (url.indexOf("index.wasm.gz") !== -1) {
      if (gzMode === "404") return Promise.resolve(new Response("not here", { status: 404 }));
      const buf = gzMode === "truncated" ? truncatedGz : goodGz;
      return Promise.resolve(new Response(buf, { status: 200, headers: { "content-type": "application/gzip" } }));
    }
    if (url === "index.wasm") {
      if (rawMode === "404") return Promise.resolve(new Response("gone", { status: 404 }));
      return Promise.resolve(new Response(payload, { status: 200, headers: { "content-type": "application/wasm" } }));
    }
    return Promise.resolve(new Response("passthrough:" + url, { status: 200 }));
  },
};
eval(script); // installs window.fetch (the shim)

let failures = 0;
function ok(cond, what) {
  console.log((cond ? "  ok   " : "  FAIL ") + what);
  if (!cond) failures++;
}

(async () => {
  // 1. a good .gz -> the whole decompressed file
  let r = await window.fetch("index.wasm");
  let buf = Buffer.from(await r.arrayBuffer());
  ok(buf.equals(payload), "a good .gz hands over the whole decompressed file (" + buf.length + " bytes)");
  ok(r.ok && r.status === 200, "the whole-file response says 200");

  // 2. a truncated .gz -> clean rejection inside, fallback to the raw file
  calls.length = 0;
  gzMode = "truncated";
  r = await window.fetch("index.wasm");
  buf = Buffer.from(await r.arrayBuffer());
  ok(buf.equals(payload), "a truncated .gz falls back to the raw wasm, whole");
  ok(calls.indexOf("index.wasm.gz") !== -1 && calls.indexOf("index.wasm") !== -1,
    "both URLs were asked in order: " + calls.join(" -> "));

  // 3. a missing .gz -> fallback to the raw file
  calls.length = 0;
  gzMode = "404";
  r = await window.fetch("index.wasm");
  buf = Buffer.from(await r.arrayBuffer());
  ok(buf.equals(payload), "a missing .gz falls back to the raw wasm, whole");

  // 4. a non-wasm URL passes through untouched
  calls.length = 0;
  r = await window.fetch("index.pck");
  const body = await r.text();
  ok(body === "passthrough:index.pck", "a non-wasm URL passes through untouched");
  ok(calls.join() === "index.pck", "the passthrough asked only for itself");

  // 5. both sides missing -> a rejection the engine's retry can take
  gzMode = "404";
  rawMode = "404";
  let rejectedCleanly = false;
  await window.fetch("index.wasm").then(
    () => ok(false, "a 404 on both sides should reject"),
    (e) => { rejectedCleanly = true; ok(true, "a 404 on both sides rejects cleanly: " + e.message); }
  );
  if (!rejectedCleanly && failures) { /* counted above */ }

  // The Request-object form (the engine may hand fetch a Request).
  gzMode = "good"; rawMode = "good";
  const req = { url: "index.wasm", method: "GET" };
  r = await window.fetch(req);
  buf = Buffer.from(await r.arrayBuffer());
  ok(buf.equals(payload), "a Request object for the wasm takes the same whole-file path");

  if (failures) { console.log("wasm_gz: " + failures + " FAILURE(S)"); process.exit(1); }
  console.log("wasm_gz: all checks passed");
})();
