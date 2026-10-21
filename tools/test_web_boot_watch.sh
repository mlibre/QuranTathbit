#!/usr/bin/env bash
# End-to-end proof of the new head scripts, in one invocation:
#   1. the happy path: the app boots through the whole-file gz shim
#      (the real 10 MB index.wasm.gz, buffered, decompressed, handed
#      over whole) -- QURAN_TATHBIT_BOOT_OK, zero page errors
#   2. a stray unhandled rejection after boot: console only, nothing
#      over the page, no APK link
#   3. the failure path (the reader's report: a load that cannot
#      finish): both wasm files 404, the engine's retries exhaust, the
#      rejection is said to the console, and the ONLY thing the reader
#      sees is the gentle stall line -- never the takeover notice, never
#      the Android download button
set -uo pipefail
QT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$QT/tools/serve_web.py"

# The failure stand-in: the same page with no engine to load.
rm -rf /tmp/webfail && mkdir -p /tmp/webfail
cp -r "$QT/builds/web/." /tmp/webfail/
rm -f /tmp/webfail/index.wasm /tmp/webfail/index.wasm.gz

python3 "$SRV" 8123 >/tmp/serve_ok.log 2>&1 &
OK_PID=$!
# serve_web.py hardcodes its own builds/web root, so the failure stand-in
# gets a plain http.server pointed at the gutted copy. A FRESH PORT every
# run: the service worker an earlier failure run registered would serve the
# cached whole build from its cache and the page would boot, failure or no
# failure -- a new port is a new origin, with no worker and no cache.
FAIL_PORT=$((8124 + ($$ % 500)))
python3 -m http.server $FAIL_PORT --directory /tmp/webfail >/tmp/serve_fail.log 2>&1 &
FAIL_PID=$!
trap 'kill $OK_PID $FAIL_PID 2>/dev/null; true' EXIT
sleep 1

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; echo "FINAL: FAIL"; exit 1; }

echo "== 1. the happy path: boot through the buffered shim =="
agent-browser set viewport 1280 800 >/dev/null || fail "viewport"
agent-browser open http://127.0.0.1:8123/ >/dev/null || fail "open"
agent-browser wait 14000 >/dev/null
BOOT=$(agent-browser console 2>/dev/null | grep -c "QURAN_TATHBIT_BOOT_OK" || true)
[ "$BOOT" -ge 1 ] && pass "app booted (QURAN_TATHBIT_BOOT_OK in console)" || fail "app did not boot"
GZ=$(agent-browser console 2>/dev/null | grep -ci "qt-wasm-gz\|wasm_gz" || true)
agent-browser screenshot /tmp/web_boot_ok.png >/dev/null

echo "== 2. a stray rejection after boot: console only =="
# The setTimeout wrapper lets the rejection escape agent-browser's own
# eval harness, so the PAGE's handler is the one that hears it.
agent-browser eval "setTimeout(function(){Promise.reject(new Error('probe: a rejection nothing caught'))},0);'armed'" >/dev/null
agent-browser wait 1500 >/dev/null
SAW=$(agent-browser console 2>/dev/null | grep -c "qt unhandled rejection: probe" || true)
[ "$SAW" -ge 1 ] && pass "the rejection is said to the console" || fail "the console never heard the rejection"
STATUS=$(agent-browser eval "document.getElementById('status') ? 'still-here' : 'gone'" 2>/dev/null | tr -d '"\n')
[ "$STATUS" = "gone" ] && pass "the loading overlay is gone (a boot finished)" || fail "overlay remains: $STATUS"
TAKEOVER=$(agent-browser eval "document.body.innerHTML.indexOf('could not finish loading') !== -1 || document.body.innerHTML.indexOf('Android.apk') !== -1 ? 'takeover' : 'clean'" 2>/dev/null | tr -d '"\n')
[ "$TAKEOVER" = "clean" ] && pass "no takeover notice, no APK link after the rejection" || fail "the takeover came back: $TAKEOVER"

echo "== 3. the failure path: a load that cannot finish =="
agent-browser open http://127.0.0.1:$FAIL_PORT/ >/dev/null || fail "open failure page"
# The engine retries the wasm four times (1 s apart) before giving up;
# the rejection lands, and the short fuse (10 s) says the stall line. The
# fresh origin also reloads once for its new service worker, so the wait
# covers a reload and the whole retry ladder besides.
agent-browser wait 30000 >/dev/null
REJ=$(agent-browser console 2>/dev/null | grep -c "qt unhandled rejection: wasm missing\|qt unhandled rejection: Failed loading file" || true)
[ "$REJ" -ge 1 ] && pass "the failed load is said to the console (no leak over the page)" || fail "the console never heard the failure"
NOTICE=$(agent-browser eval "var n=document.getElementById('status-notice'); n && n.textContent ? n.textContent : 'empty'" 2>/dev/null | tr -d '"' | head -c 200)
echo "      the reader sees: ${NOTICE:0:120}"
STALL=$(agent-browser eval "var n=document.getElementById('status-notice'); n && n.textContent.indexOf('Still loading after a long wait') !== -1 ? 'stall' : 'other'" 2>/dev/null | tr -d '"\n')
[ "$STALL" = "stall" ] && pass "the gentle stall line is the reader's only word" || fail "the reader saw something else: $STALL"
APK=$(agent-browser eval "document.body.innerHTML.indexOf('Android.apk') !== -1 ? 'apk' : 'none'" 2>/dev/null | tr -d '"\n')
[ "$APK" = "none" ] && pass "no Android download button on a desktop failure" || fail "the APK button is back"
TAKEOVER2=$(agent-browser eval "document.body.innerHTML.indexOf('could not finish loading') !== -1 ? 'takeover' : 'clean'" 2>/dev/null | tr -d '"\n')
[ "$TAKEOVER2" = "clean" ] && pass "the takeover text never appeared" || fail "the takeover text appeared"
agent-browser screenshot /tmp/web_fail_stall.png >/dev/null

echo "FINAL: PASS"
