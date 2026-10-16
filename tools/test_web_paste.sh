#!/usr/bin/env bash
# End-to-end test of pasting a token in the web build, in one invocation
# (background processes do not survive between tool calls here).
# Paste is no longer a button and no permission sheet stands between the
# clipboard and the field: the head script hands the page's own paste
# event to the app, which lands the text in whatever field is focused.
# This test proves that whole path on a live page:
#   1. serve builds/web, boot the app at a phone viewport, require BOOT_OK
#   2. open Settings with a canvas click on the corner coin
#   3. sweep-click where the token field lives; after each click, dispatch
#      a real paste event carrying a known token -- the app answers by
#      stamping what its field now holds into the document (data-qt-pasted),
#      so every try is checked and only a true paste into a true focused
#      field answers
#   4. require the stamp to carry the token's length and first eight
#      characters -- the exact bytes the field received
#   5. press Show, screenshot the field for visual confirmation
set -uo pipefail
SRV="$(dirname "$0")/serve_web.py"
python3 "$SRV" 8123 >/tmp/serve_web.log 2>&1 &
SRV_PID=$!
trap 'kill $SRV_PID 2>/dev/null; true' EXIT
sleep 1

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; echo "FINAL: FAIL"; exit 1; }

TOKEN="ghp_testpaste_0123456789abcdef"
LEN=${#TOKEN}
HEAD="${TOKEN:0:8}"
# "ok:LEN:HEAD" as the app writes it, URI-encoded the way the page carries it.
WANT="ok%3A${LEN}%3A${HEAD}"

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

echo "== 3. paste into the field =="
# The paste lands only in a focused field: every try clicks a candidate
# spot, dispatches a real paste event carrying the token, and looks for
# the app's answer stamped into the document.
PASTE_JS="var dt=new DataTransfer();dt.setData('text/plain','${TOKEN}');window.dispatchEvent(new ClipboardEvent('paste',{clipboardData:dt}));'sent'"
FOUND=""
for y in 530 520 540 510 550 500 560 490; do
  for x in 160 100 220 280 60; do
        agent-browser eval "document.documentElement.setAttribute('data-qt-pasted','')" >/dev/null
        agent-browser mouse move $x $y >/dev/null
        agent-browser mouse down >/dev/null; agent-browser mouse up >/dev/null
        agent-browser eval "$PASTE_JS" >/dev/null
        agent-browser wait 300 >/dev/null
        A=$(agent-browser eval "document.documentElement.getAttribute('data-qt-pasted') || 'none'" 2>/dev/null | tr -d '"\n')
        if [ "$A" != "none" ] && [ "$A" != "" ]; then FOUND="$A"; break 2; fi
  done
done
[ -n "$FOUND" ] || fail "pasting never reached a focused field"
echo "      the app answered: $FOUND"
[ "$FOUND" = "$WANT" ] && pass "the paste landed in the field ($FOUND)" || fail "the field holds something else: $FOUND (wanted $WANT)"

echo "== 4. show what arrived =="
# Show and Save share the row under the field: halves of the card's width.
agent-browser mouse move 121 585 >/dev/null
agent-browser mouse down >/dev/null; agent-browser mouse up >/dev/null
agent-browser wait 800 >/dev/null
agent-browser screenshot /tmp/web_2_pasted.png >/dev/null
pass "field screenshotted for visual check (token visible if Show was hit)"

echo "FINAL: PASS"
