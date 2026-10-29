# Fullscreen bar auto-hide on niri

In Settings > Bar, enable **Use overlay layer**, then **Hide bar on fullscreen**
for the desired bar. Both settings default to off. Existing configurations
keep their layer and visibility behavior.

When the active window of that output's visible workspace is fullscreen,
the top bar slides away with the normal auto-hide animation. It slides back
when fullscreen ends. Animation timing follows the current theme, including
the disabled-animation setting. Moving keyboard focus to another
output does not by itself reveal the bar. Moving the pointer to the screen
edge or using `dms ipc call bar toggleReveal index 0` reveals it. Open popouts
follow the existing strict-auto-hide setting. Overview follows the existing
overview reveal settings. Animation speed, including disabled animations,
continues to follow the theme.

The option does not enable global auto-hide or change the bar's layer. It is
inactive on non-overlay surfaces, including an explicit `DMS_DANKBAR_LAYER`
override to Top, and does not change frame-hosted bars or other compositors.
Fullscreen hiding preserves the configured exclusive zone to avoid resizing
background windows.

Niri IPC provides workspace membership but no fullscreen state. The Wayland
toplevel protocol provides fullscreen state but no shared window ID. Matching
uses exact application ID and title on the output, disambiguated by keyboard
focus when available. If equal titles on the same output remain ambiguous,
the bar stays available rather than selecting an arbitrary window. Transient
title or output mismatches also leave it available until the data agrees.

Regression tests (Node.js, no npm dependencies):

```
node --test quickshell/tests/niri-fullscreen.test.mjs quickshell/tests/bar-ipc.test.mjs
```
