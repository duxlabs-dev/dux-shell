---
name: dms-sandbox-theme
description: >
  Runs DMS theme generation (`dms matugen generate`) from a local build in an
  isolated sandbox. Intended to leave the developer's live desktop, terminals and config files untouched.
  Compares the output against an upstream ref.
  Use when testing changes to matugen or dank16 or theme generation inputs, or to check for regressions in configs.
---

# Sandboxed DMS theme generation

`dms matugen generate` writes real app configs and pokes the live session. Running a dev
build of it directly rewrites the developer's ghostty/kitty/GTK themes and sends their
terminals reload signals. `scripts/run.sh` makes sure sandbox testing doesn't leak.

| Side effect of a real run | How run.sh contains it |
|---|---|
| Template outputs under `~/.config`, `~/.local/share`, `~/.cache` | HOME and every XDG dir point inside OUT_DIR |
| SIGUSR1/SIGUSR2 to running kitty/ghostty (found via /proc) | Own PID namespace: no real processes visible |
| gsettings `color-scheme` toggle, fcitx5 reload over D-Bus | `DBUS_SESSION_BUS_ADDRESS` points at a missing socket |

It uses `unshare --map-current-user` (not `-r`: dms refuses to run as root) and needs
`unshare` (util-linux), `go`, `python3` and `matugen` on PATH. Run the scripts with **bash**:
under zsh, unquoted flag strings are not word-split and arrive as one argument.

Paths below are relative to the repo root; `SKILL=.agents/skills/dms-sandbox-theme`.

## Scripts

- `$SKILL/scripts/run.sh BINARY SHELL_DIR OUT_DIR [--stock COLORS_JSON] [generate flags...]`:
  one sandboxed run. OUT_DIR is created anew or is wiped (if it is tagged with `.dms-sandbox`).
  Paths are made absolute by the script; a relative state dir breaks generation.
- `$SKILL/scripts/gen_stock.py THEME_JSON {dark|light} [--dark-variant FLAVOR/ACCENT] [--light-variant ...]`:
  builds the `--stock-colors` JSON the shell passes for a registry or custom theme, e.g. an
  installed one under `~/.config/dms/themes/<id>/theme.json`. Variants default
  to the theme's own defaults. Generate it **for the mode you run**: the `default` variant
  follows the mode, and a dark-default file in a light run mixes dark roles with light
  terminal colors, which looks like a bug in the code under test.
- `$SKILL/scripts/compare.sh REPO REF WORK_DIR [run.sh args after OUT_DIR...]`: builds REF
  with `git archive` (the working tree is untouched; builds are cached per commit in
  WORK_DIR), builds the working tree, runs three cases with the same args and diffs them:
  `ref` (REF binary + REF shell), `branch` (working tree), `cross` (REF binary + working-tree
  shell, since a shell newer than the binary is a supported setup). Exits 0 only if all three
  generate and their app configs are identical.

Keep WORK_DIR and OUT_DIR outside the repo (a temp or scratch directory).

## Recipes

Registry theme, dark (using bru theme because it's a good test; its dark `primary_container` causes contrast problems):
```bash
SKILL=.agents/skills/dms-sandbox-theme W=$(mktemp -d)
python3 -I $SKILL/scripts/gen_stock.py ~/.config/dms/themes/bru/theme.json dark > $W/stock.json
bash $SKILL/scripts/compare.sh . master $W/cmp \
  --stock $W/stock.json --kind hex --value '#dbb32d' --mode dark
```

Wallpaper-style path (matugen computes the roles): drop `--stock ...`, keep `--kind hex --value <seed>`.
Light mode: regenerate the stock JSON with `light` and pass `--mode light`.
Other paths worth covering when a change touches palette code: `--spec 2025`,
`--terminals-always-dark` (terminal templates switch `.default.` to `.dark.`),
`--terminal-palette medium`, `--terminal-opacity 85`.

Single run with new flags, then inspect:
```bash
bash $SKILL/scripts/run.sh $W/cmp/dms-branch quickshell $W/out \
  --stock $W/stock.json --kind hex --value '#dbb32d' --mode dark <flags under test...>
grep -E '^palette = ' $W/out/config/ghostty/themes/dankcolors
```
Outputs: `out/config/...` (ghostty, kitty, alacritty, gtk-3.0/4.0, zed, niri...),
`out/data/color-schemes/` (KDE), `out/state/dms-colors.json` (what the shell itself reads).
Only apps whose command is on PATH get rendered, as in a real run.

## Troubleshooting

- **Defaults changed when new behavior not requested.** `ref vs branch` should report
  `identical`. If only `dms-colors.json` differs, check the summary line: existing sections
  unchanged, only additions. The shell parses it as JSON, so key order and indentation
  don't matter.
- **`cross` failing** means the new shell needs the new binary. Matugen aborts the whole
  template (`ResolveError`) on an undefined `{{var}}`, so a template referencing a namespace
  only the new binary injects breaks older binaries, and a broken `dank.json` stops the
  shell's own colors updating. Prefer having Go add content (for example in `renderColors`
  or `applyTerminalTemplate`) over new template variables.
- A failed generate leaves no output; read `WORK_DIR/<case>.log` (ANSI-colored; strip with
  `sed 's/\x1b\[[0-9;]*m//g'`). "folder doesnt exist, trying to create" lines are normal.
- Report what was compared (ref sha, flags, mode) alongside the verdict.
