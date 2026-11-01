## What is this?

DMS is an open-source desktop shell for Wayland compositors on linux, built to work with many compositors.

## Repo Structure

- core/ - Go. `cmd/dms` runs quickshell, CLI utilities, and the unix socket server the UI depends on. `cmd/duxinstall` is a separate installer TUI.
- quickshell/ - the entire UI: Common/ (singletons, Theme, settings), Services/ (system and core access), Modules/ (bar, dock, lock, ...), Modals/, Widgets/ (shell-specific widgets and deprecated Dank* shims), PLUGINS/, translations/
- dux-qml-common/ - submodule of shared QML widgets
- docs/, distro/ - IPC and theme docs, packaging

## Rules

- Keep it simple.
- Do not edit code in response to a question.
- Never commit, push, or open a PR unless asked.
- Point out glaring issues we missed.
- The shell runs 24/7. Audit every change for idle CPU, extra processes, timers, and retained memory.
- `core` and `quickshell` share the socket protocol. Changing one means checking the other.
- QML uses Theme tokens, never hardcoded colors, spacing, or constants.
- Use the D* widgets from qs.DCommon.Widgets (DListView, DFlickable, and so on) instead of raw ListView/Flickable/ScrollView. The Dank* names in Widgets/ are deprecated shims.
- User-facing text goes through I18n.tr(). Reuse catalog terms. Never edit translation catalogs.
- Guard clauses, early returns.
- Comment only what the code cannot say: a non-obvious why, a trap, a workaround. Never narrate what the code does or restate a name. Keep it to a line or two, and delete useless or paragraph comments you come across.
- Do not edit generated code. Mocks come from mockery.
- No library for a simple problem. Use a modern one for a complex, common problem.

## Tests

- A test must fail on the broken code. Otherwise do not write it.
- No useless tests: "main.go contains func main()", defaults, "it instantiates", behavior the change didn't touch.
- QML tests must be fast. Call logic directly, load the smallest component, no fixed delays or animation waits, few meaningful assertions over a matrix.
- Tests cover `.js` modules, functions of `Services/` and `Common/` singletons, and IPC handlers. Never load, slice or mock anything under `Modules/`, `Modals/` or `Widgets/`, and never spawn a compositor, display server or shell. Those tests only ever broke on UI tweaks.

## Connections vs bound properties

- In per-item or per-screen components (delegates, bar widgets, popout and modal hosts, OSDs), no `Connections` for `on<Prop>Changed` handlers.
- Source in the same file: put the handler on it.
- Source outside (singleton, loader item, delegate parent): bind to a typed readonly property, never `var`, and handle that.
- Keep `Connections` for plain signals, hand-emitted change signals (`SettingsData.barConfigsChanged()`), constant-pointer targets, reassignable targets, and per-frame `var` sources.
- A bound handler fires once at creation if the initial value differs from the type default, and never on a same-value write. Convert only idempotent bodies. `enabled:` conditions become a guard inside the handler.
- Singletons under Services/ and Common/ keep their `Connections`.

## Commit Messages

`area: short lowercase explanation`, for example `network: report wifi state from the associated adapter`. Description only if required, in simple language.
