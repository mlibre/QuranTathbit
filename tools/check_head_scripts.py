#!/usr/bin/env python3
"""Extract every inline <script> body from an HTML file and node --check it.

The page's head scripts (browser-keys, bridges, guards, watches) are
grep-checked by CI, but a script can carry its marker AND be dead -- a
missing </script>, a real newline inside a string literal. This walks
the DOM the way a browser does (split on open/close tags) and hands each
inline script body to node --check, so a dead script fails the build.

The SIMD guard's probe is checked one step further, semantically: the
bytes it hands WebAssembly.validate must themselves validate on this
runner's engine. The probe that shipped before this check declared a
section size its payload did not carry, so every engine on earth answered
"no SIMD" -- a guard with such a probe blocks every reader, telling each
one their browser cannot run what it can.
"""

import json
import re
import subprocess
import sys
import tempfile
import os

path = sys.argv[1]
html = open(path, encoding="utf-8").read()

# Walk script elements the way the HTML parser does: an inline script's
# body runs from after <script ...> to the next </script>.
bodies = []
for m in re.finditer(r"<script\b[^>]*>(.*?)</script>", html, re.DOTALL):
    body = m.group(1)
    # Skip external scripts (src=) -- their body is empty or a comment.
    open_tag = html[m.start():m.end(1)]
    if re.search(r"<script\b[^>]*\bsrc=", open_tag):
        continue
    if body.strip():
        bodies.append((m.start(), body))

print(f"{path}: {len(bodies)} inline script(s)")
failed = 0
for i, (pos, body) in enumerate(bodies):
    line = html.count("\n", 0, pos) + 1
    with tempfile.NamedTemporaryFile(
        "w", suffix=".js", delete=False, encoding="utf-8"
    ) as f:
        f.write(body)
        tmp = f.name
    r = subprocess.run(
        ["node", "--check", tmp], capture_output=True, text=True
    )
    os.unlink(tmp)
    if r.returncode != 0:
        failed += 1
        first = body.strip().split("\n")[0][:60]
        print(f"  FAIL script #{i} (line {line}, starts {first!r})")
        for err_line in r.stderr.strip().splitlines()[:4]:
            print(f"       {err_line}")
    else:
        first = body.strip().split("\n")[0][:50]
        print(f"  ok   script #{i} (line {line}, starts {first!r})")


# ---- the SIMD guard's probe must itself validate ----
# (runs only when the page carries the guard; the check demands that the
# bytes the guard hands WebAssembly.validate are a true SIMD module, so a
# malformed probe cannot quietly block every reader.)
simd_script = next((b for _, b in bodies if "qt-simd-guard" in b), None)
if simd_script is None:
    print("simd guard: not present (no probe to check)")
    sys.exit(1 if failed else 0)

probe_match = re.search(
    r"qt-simd-guard.*?new Uint8Array\((\[[\d,]+\])\)", simd_script, re.DOTALL
)
if not probe_match:
    print("  FAIL simd guard: no WebAssembly.validate probe found")
    sys.exit(1)
probe_bytes = json.loads(probe_match.group(1))
checker = (
    "const b=new Uint8Array(%s);"
    "if(!WebAssembly.validate(b)){console.error('probe does not validate');process.exit(1)}"
    "console.log('ok: simd guard probe validates as a true SIMD module')"
) % (json.dumps(probe_bytes),)
r = subprocess.run(["node", "-e", checker], capture_output=True, text=True)
print(r.stdout.strip() or r.stderr.strip())
if r.returncode != 0:
    print("  FAIL simd guard: the probe bytes are not a valid SIMD module --"
          " the guard would block every reader")
    sys.exit(1)

sys.exit(1 if failed else 0)
