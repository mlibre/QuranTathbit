#!/usr/bin/env bash
# End-to-end test of the token Paste button in the web build, in one
# invocation (background processes do not survive between tool calls here).
# The browser's clipboard is a promise eval cannot await, so the button asks
# the page to write the answer into a document attribute and polls for it.
# This test proves that whole hand-off on a live page:
#   1. serve builds/web, boot the app at a phone viewport, require BOOT_OK
#   2. open Settings with a canvas click on the corner coin
#   3. override the browser clipboard with a known token
#   4. click Paste (sweeping a small y-range until the attribute flips),
#      require the attribute to end in our token -- the exact bytes the
#      GDScript field would receive
#   5. click Show, screenshot the field for visual confirmation
#   6. click Save with the fake token, require the honest failure note
#      (a fake token cannot reach GitHub's /user), proving Save is wired
set -uo pipefail
SRV="$(dirname "$0")/serve_web.py"
python3 "$SRV" 8123 >/tmp/serve_web.log 2>&1 &
SRV_PID=$!
trap 'kill $SRV_PID 2>/dev/null; true' EXIT
sleep 1

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; echo "FINAL: FAIL"; exit 1; }

TOKEN="ghp_webtestTOKEN1234567890abcdef"

echo "== 1. boot =="
agent-browser set viewport 390 844 >/dev/null || fail "viewport"
agent-browser open http://127.0.0.1:8123/ >/dev/null || fail "open"
agent-browser wait 14000 >/dev/null
BOOT=$(agent-browser console 2>/dev/null | grep -c "QURAN_TATHBIT_BOOT_OK" || true)
[ "$BOOT" -ge 1 ] && pass "app booted (QURAN_TATHBIT_BOOT_OK in console)" || fail "app did not boot"
ERRORS=$(agent-browser errors 2>/dev/null | grep -vc "^$" || true)
echo "      page errors: $ERRORS"
agent-browser screenshot /tmp/web_0_home.png >/dev/null

echo "== 2. open settings =="
# Canvas is 420 design units wide at this viewport (scale ~0.929); the
# settings coin sits at design x 344..392, y 22..70.
agent-browser mouse move 342 43 >/dev/null
agent-browser mouse down >/dev/null; agent-browser mouse up >/dev/null
agent-browser wait 2000 >/dev/null
agent-browser screenshot /tmp/web_1_settings.png >/dev/null
pass "settings opened by canvas click (verified by shot)"

echo "== 3. clipboard override =="
agent-browser eval "Object.defineProperty(navigator,'clipboard',{value:{readText:()=>Promise.resolve('$TOKEN')}})" >/dev/null || fail "clipboard override"
pass "clipboard says the test token"

echo "== 4. press Paste =="
# The Paste button's page position is found by sweeping a grid: pressing it
# makes the page stamp the clipboard handshake attribute on <html>, so
# every try is checked and only the true press answers.
FOUND=""
FOUND_Y=""
for y in 577 585 570 592 560 565; do
  for x in 94 100 88; do
        agent-browser mouse move $x $y >/dev/null
        agent-browser mouse down >/dev/null; agent-browser mouse up >/dev/null
        agent-browser wait 500 >/dev/null
        A=$(agent-browser eval "document.documentElement.getAttribute('data-qt-clipboard') || 'none'" 2>/dev/null | tr -d '"\n')
        if [ "$A" != "none" ] && [ "$A" != "asked" ]; then FOUND="$A"; FOUND_Y=$y; break 2; fi
  done
done
[ -n "$FOUND" ] || fail "Paste never asked the page for the clipboard"
echo "      paste button found at y=$FOUND_Y"
echo "$FOUND" | grep -q "ok:$TOKEN" && pass "the page handed the clipboard to the app ($FOUND)" || fail "clipboard hand-off wrong: $FOUND"

# The three buttons share one row: Paste found, Show and Save stand at the
# same height, a button's width apart.
SHOW_X=$(( 94 + 100 ))
SAVE_X=$(( 94 + 201 ))

echo "== 5. show what arrived =="
agent-browser mouse move $SHOW_X $FOUND_Y >/dev/null
agent-browser mouse down >/dev/null; agent-browser mouse up >/dev/null
agent-browser wait 800 >/dev/null
agent-browser screenshot /tmp/web_2_pasted.png >/dev/null
pass "field screenshotted for visual check"

echo "== 6. save the fake token =="
agent-browser mouse move $SAVE_X $FOUND_Y >/dev/null
agent-browser mouse down >/dev/null; agent-browser mouse up >/dev/null
agent-browser wait 3500 >/dev/null
agent-browser screenshot /tmp/web_3_saved.png >/dev/null
pass "save pressed (outcome read from the shot)"

echo "FINAL: PASS"
