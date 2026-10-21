#!/usr/bin/env node
// The boot watch's new law, proven on the exact script bytes the built
// page carries: an error or an unhandled promise is said to the console
// and never over the reader's page; the one word to the reader is the
// gentle stall line (45 s of a frozen bar, or 10 s once a rejection has
// been seen), and it never offers the APK; a guard that has spoken owns
// the page and the watch stays quiet for good.
//
// Tick arithmetic: each ticker() call is one 5 s poll. The FIRST poll
// after the watch installs only establishes the bar's baseline (v!==null
// resets the counter), so a scenario counts from the second poll.
const fs = require("fs");
const path = require("path").join(__dirname, "..", "builds", "web", "index.html");
const html = fs.readFileSync(path, "utf8");

const m = html.match(/<script>(\/\*qt-boot-watch\*\/.*?)<\/script>/s);
if (!m) { console.error("FAIL: qt-boot-watch script not found in built page"); process.exit(1); }
const script = m[1];

const handlers = {};
let ticker = null;
let notices = [];
let errors = [];
const install = () => {
  globalThis.window = {
    addEventListener: (name, fn) => { handlers[name] = fn; },
    __qtNotice: (en, fa, opts) => { notices.push({ en, fa, opts }); },
    __qtWebGL2Missing: false,
    __qtWasmSimdMissing: false,
  };
  notices = [];
  errors = [];
  eval(script);
};

globalThis.document = {
  getElementById: (id) => {
    if (id === "status-progress") return { hasAttribute: () => true, getAttribute: () => "42" };
    if (id === "status") return { style: { visibility: "visible" } };
    return null;
  },
};
globalThis.setInterval = (fn) => { ticker = fn; return 0; };
const realError = console.error;
console.error = (...a) => { errors.push(a.join(" ")); };

let failures = 0;
function ok(cond, what) {
  console.log((cond ? "  ok   " : "  FAIL ") + what);
  if (!cond) failures++;
}
const STALL = "Still loading after a long wait.";

// A. an unhandled rejection: console only, never the page
install();
handlers["unhandledrejection"]({ reason: new Error("the link dropped") });
ok(errors.length === 1 && errors[0].indexOf("the link dropped") !== -1,
  "an unhandled rejection is said to the console: " + JSON.stringify(errors));
ok(notices.length === 0, "the rejection shows nothing over the reader's page");

// B. the short fuse: a seen rejection arms 10 s, not 45
install();
ticker(); // baseline: the bar's value is learned, still = 0
handlers["unhandledrejection"]({ reason: new Error("dropped again") });
ticker(); // 5 s
ok(notices.length === 0, "5 s of frozen bar says nothing yet");
ticker(); // 10 s
ok(notices.length === 1 && notices[0].en.indexOf(STALL) !== -1,
  "a frozen bar with a seen rejection says the stall line at 10 s");
ok(!notices[0].opts || !notices[0].opts.apk, "the stall line offers no APK");
ticker(); ticker();
ok(notices.length === 1, "the stall line is said once, and never again");

// C. a page error: console only
errors = [];
handlers["error"]({ message: "a script stumbled" });
ok(errors.length === 1 && errors[0].indexOf("a script stumbled") !== -1,
  "a page error is said to the console too");
ok(notices.length === 1, "the error adds nothing over the page");

// D. the long fuse: no rejection seen, 45 s of frozen bar
install();
ticker(); // baseline
for (let i = 0; i < 8; i++) ticker(); // 40 s
ok(notices.length === 0, "40 s of a frozen bar that never saw a rejection still says nothing");
ticker(); // 45 s
ok(notices.length === 1 && notices[0].en.indexOf(STALL) !== -1,
  "the stall line arrives at 45 s without a rejection");
ok(!notices[0].opts || !notices[0].opts.apk, "the long-fuse stall line offers no APK either");

// E. a guard that has spoken owns the page: the watch stays quiet
install();
globalThis.window.__qtWebGL2Missing = true;
handlers["unhandledrejection"]({ reason: new Error("whatever") });
for (let i = 0; i < 20; i++) ticker();
ok(notices.length === 0, "a guard that has spoken keeps the watch quiet for good");
ok(errors.length >= 1, "even then, the console still hears the reason");

console.error = realError;
if (failures) { console.log("boot_watch: " + failures + " FAILURE(S)"); process.exit(1); }
console.log("boot_watch: all checks passed");
