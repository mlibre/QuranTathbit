#!/usr/bin/env node
// The web paste's one-arrival law, proven on the exact script bytes the
// page carries (extracted from export_presets.cfg's head_include, the
// same place the build takes them).
//
// The shape of the bug this test holds the line against: the browser's
// paste event delivered the words once, and the keyup of the same Ctrl+V
// re-armed the clipboard-read fallback with a FRESH seen-count baseline --
// the fallback's guard (has the paste been seen since I was armed?) then
// passed, and navigator.clipboard.readText delivered the same words a
// second time, ~120 ms after the keyup. Every paste was written twice.
//
// Scenarios:
//   1. paste event + keyup          -> exactly one delivery  (the old double)
//   2. paste event never arrives    -> exactly one delivery  (the fallback lives)
//   3. two event-less presses 200ms apart -> two deliveries (no over-suppression)
//   4. the reader's Ctrl+A -> Ctrl+X -> Ctrl+V -> one cut, one paste
//   5. two normal pastes a second apart -> two deliveries (recency never
//      stands between a reader and a deliberate paste)
//   6. Ctrl+X / Ctrl+C answered on the keydown only, and both shapes of
//      Ctrl+V stay stopped from reaching the engine

const fs = require("fs");
const path = require("path");
const cfg = fs.readFileSync(
  path.join(__dirname, "..", "export_presets.cfg"),
  "utf8"
);

function extract(name) {
  const m = cfg.match(new RegExp("<script>/\\*" + name + "\\*/(.*?)</script>"));
  if (!m) {
    console.error("FAIL: " + name + " script not found in export_presets.cfg");
    process.exit(1);
  }
  return m[1];
}

let failures = 0;
let checks = 0;
function ok(cond, what) {
  checks++;
  console.log((cond ? "  ok   " : "  FAIL ") + what);
  if (!cond) failures++;
}

// ---- the fake page -------------------------------------------------------
let handlers = {};
let deliveries = [];
let cuts = [];
let clipText = "";
let readTextAllowed = true;

function freshPage() {
  handlers = {};
  deliveries = [];
  cuts = [];
  const stamp = { stopped: 0 };
  globalThis.window = {
    addEventListener: (name, fn) => {
      handlers[name] = fn;
    },
  };
  Object.defineProperty(globalThis, "navigator", {
    value: {
      clipboard: {
        readText: async () => {
          if (!readTextAllowed) throw new Error("denied");
          return clipText;
        },
        writeText: async (t) => {
          clipText = t;
        },
      },
    },
    configurable: true,
  });
  globalThis.document = {
    createElement: () => ({ select() {}, remove() {}, setAttribute() {} }),
    body: { appendChild() {} },
    execCommand: () => true,
  };
  // The engine's hook and the page's hooks, the way boot installs them.
  eval(extract("qt-paste-bridge"));
  eval(extract("qt-browser-keys"));
  window.__qtPasteInstall.install((text) => deliveries.push(text));
  window.__qtClipInstall.install(() => cuts.push(1));
  window.__qtClipOn = true;
  return stamp;
}

// A key event the way the browser hands it over.
function key(type, code, opts = {}) {
  const stops = { stopImmediate: 0 };
  const e = {
    type,
    key: opts.key || code.replace("Key", "").toLowerCase(),
    code,
    ctrlKey: true,
    altKey: false,
    shiftKey: false,
    stopImmediatePropagation() {
      stops.stopImmediate++;
    },
    stopPropagation() {},
  };
  handlers[type] && handlers[type](e);
  return stops;
}

// The browser's own paste: the words leave for the field and the page's
// listener is told, once.
function browserPaste(text) {
  clipText = text;
  handlers["paste"]({
    target: { tagName: "CANVAS" },
    clipboardData: { getData: () => text },
    stopImmediatePropagation() {},
    preventDefault() {},
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- the scenarios -------------------------------------------------------

(async () => {
  console.log("the web paste lands once");

  // 1. The old double: the paste event delivers, then the keyup of the
  // same Ctrl+V re-arms the fallback. One delivery, not two.
  {
    freshPage();
    key("keydown", "KeyV");
    browserPaste("hello");
    key("keyup", "KeyV");
    await sleep(250);
    ok(
      JSON.stringify(deliveries) === JSON.stringify(["hello"]),
      "paste event + keyup delivers exactly once (got " +
        JSON.stringify(deliveries) + ")"
    );
  }

  // 2. A browser where the paste event never comes: the fallback reads
  // the clipboard and delivers once.
  {
    freshPage();
    key("keydown", "KeyV");
    key("keyup", "KeyV");
    await sleep(250);
    ok(
      JSON.stringify(deliveries) === JSON.stringify([clipText]),
      "an event-less press is answered once by the fallback (got " +
        JSON.stringify(deliveries) + ")"
    );
  }

  // 3. The event-less browser's second press, 200 ms after the first:
  // the fallback must answer again -- the recency guard never stands
  // between a reader and a paste.
  {
    freshPage();
    key("keydown", "KeyV");
    key("keyup", "KeyV");
    await sleep(250);
    const first = deliveries.length;
    key("keydown", "KeyV");
    key("keyup", "KeyV");
    await sleep(250);
    ok(
      first === 1 && deliveries.length === 2,
      "a second event-less press 200 ms later delivers again (got " +
        deliveries.length + ")"
    );
  }

  // 4. The reader's own sequence: type, Ctrl+A (reaches the engine), Ctrl+X
  // (the page takes the words), Ctrl+V -- one cut, one paste.
  {
    freshPage();
    window.__qtClipSel = "typed words";
    key("keydown", "KeyA"); // not the page's key: it reaches the engine
    key("keydown", "KeyX");
    key("keyup", "KeyX");
    await sleep(20);
    ok(cuts.length === 1, "the cut arrives once (got " + cuts.length + ")");
    ok(clipText === "typed words", "the cut's words went to the clipboard");
    key("keydown", "KeyV");
    browserPaste("typed words");
    key("keyup", "KeyV");
    await sleep(250);
    ok(
      JSON.stringify(deliveries) === JSON.stringify(["typed words"]),
      "select, cut, paste lands once (got " + JSON.stringify(deliveries) + ")"
    );
  }

  // 5. Two deliberate pastes a second apart: both land.
  {
    freshPage();
    key("keydown", "KeyV");
    browserPaste("first");
    key("keyup", "KeyV");
    await sleep(1000);
    key("keydown", "KeyV");
    browserPaste("second");
    key("keyup", "KeyV");
    await sleep(250);
    ok(
      JSON.stringify(deliveries) === JSON.stringify(["first", "second"]),
      "two pastes a second apart both land (got " + JSON.stringify(deliveries) + ")"
    );
  }

  // 6. The keys' shapes: a keyup alone never cuts, and both shapes of
  // Ctrl+V stay stopped from reaching the engine.
  {
    freshPage();
    window.__qtClipSel = "selected";
    key("keyup", "KeyX");
    await sleep(20);
    ok(cuts.length === 0, "a keyup alone never cuts");
    window.__qtClipSel = "";
    clipText = "carry me";
    const down = key("keydown", "KeyV");
    const up = key("keyup", "KeyV");
    ok(
      down.stopImmediate === 1 && up.stopImmediate === 1,
      "Ctrl+V is stopped before the engine on both strokes"
    );
    browserPaste("carry me");
    await sleep(250);
    ok(
      JSON.stringify(deliveries) === JSON.stringify(["carry me"]),
      "the engine never pasting leaves one delivery (got " +
        JSON.stringify(deliveries) + ")"
    );
  }

  if (failures > 0) {
    console.log("paste-bridge: " + failures + " FAILURE(S) of " + checks);
    process.exit(1);
  }
  console.log("paste-bridge: all " + checks + " checks passed");
  process.exit(0);
})();
