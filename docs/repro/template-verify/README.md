<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Consumer-verify: xiom.template 0.2.0 (PULSE side)

Scope: the packages lane's delivery on the PULSE top-tier ask
(`REL-20261015-2202-pulse-3`, item "templates/escaping") -- the registry
package `xiom.template 0.2.0` (eco-v0.1.186, sha256
`bedd03a905f760e16f5425a1c666fb94fa16d23db77b9d7d120cc3bbc7c80580`,
announced at `REL-20261016-1111-packages`). This unit consumes the
INSTALLED registry artifact -- no vendored copy -- and renders realistic
PULSE-shaped pages (a 404 error page and a docs nav page) plus the full
0.2.0 block surface, against exact hand-computed bytes.

## Result

- **15/15 checks GREEN, x2 on both platforms, on the pinned v0.64.5**
  (stdlib pin `stdlib-092dfa0c`): Windows
  (`probe-logs/template-verify/win-run{1,2}.log`) and WSL Ubuntu
  (`linux-run{1,2}.log`); the install checksum matched the published
  sha256 on both stores.
- Verified surface: v0.1 placeholder rendering (unchanged in 0.2.0),
  sections/loops (`{{#key}}...{{/key}}`, `{{.}}` item, parent-context
  resolution), inverted sections (strict existing-empty + lenient
  missing), dotted paths + context stack, auto-escaping
  (`& < > " '` -> `&amp; &lt; &gt; &quot; &#39;`) with raw
  `{{{...}}}` / `{{&...}}` forms, `escape_html=false`, bool
  truthiness, exact strict error texts with byte offsets (unknown key /
  unterminated section / mismatched close), lenient never-fails
  behavior, data accessors + kind constants, UTF-8 byte-exactness,
  empty template.
- **Consumer note (actionable):** imports bind to the registry artifact
  only when the dependency is DECLARED. Without
  `[dependencies] "xiom.template" = "0.2.0"`, `use xiom.template;`
  silently bound to a Map-based 2-arg `template_render` (the stdlib's
  `xiom.string.template` surface) while `xiom.template.blocks` stayed
  unresolved -- a consumer skipping the manifest entry gets a different,
  confusing API with no dedicated diagnostic. The `xiom.toml` in this
  unit pins the artifact; PULSE's future integration (W8 wrapper) must
  declare it in the project manifest.

## How to run

- Pinned env (Windows):
  `XIOM_COMPILER=%LOCALAPPDATA%\xiom.new-20261015-2240\bin\xiom.exe`,
  `XIOM_STDLIB=%LOCALAPPDATA%\xiom-pins\stdlib-092dfa0c`;
  WSL: `~/.local/share/xiom-v0645/bin/xiom`,
  `~/.cache/xiom-pin/stdlib-092dfa0c`.
- Install once: `xiom pkg install xiom.template@0.2.0`.
- From this directory: `xiom --run probe.xi` (exit code = failures;
  the local `xiom.toml` declares the dependency with `root = "."`).
- WSL leg ran `probe-logs/template-verify/run-linux.sh`.

## Evidence

- `probe-logs/template-verify/`: `win-run1.log`, `win-run2.log`,
  `linux-run1.log`, `linux-run2.log` (15/15 + `exit code: 0` each).
- Bus: result filed back to the packages lane (ref
  `REL-20261016-1111-packages`).
