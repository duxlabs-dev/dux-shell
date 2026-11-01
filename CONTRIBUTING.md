# Contributing

Contributions are welcome and encouraged.

To contribute fork this repository, make your changes, and open a pull request.

## Setup

Clone with submodules — the shared widget library ([dux-qml-common](https://github.com/duxlabs-dev/dux-qml-common)) is vendored at `dux-qml-common/` and symlinked into `quickshell/DCommon`:

```bash
git clone --recurse-submodules https://github.com/duxlabs-dev/dux-shell.git
# or, in an existing clone:
git submodule update --init
```

To have `git pull` keep the submodule in sync automatically (moving it to the commit this repo points at, no separate `git submodule update` step), set:

```bash
git config submodule.recurse true
```

Install [prek](https://prek.j178.dev/) then activate pre-commit hooks:

```bash
prek install
```

### Nix Development Shell

If you have Nix installed with flakes enabled, you can use the provided development shell which includes all necessary dependencies:

```bash
nix develop
```

This will provide:

- Go 1.25+ toolchain (go, gopls, delve, go-tools) and GNU Make
- Quickshell and required QML packages
- Properly configured QML2_IMPORT_PATH

The dev shell automatically creates the `.qmlls.ini` file in the `quickshell/` directory.

## Building and running

The Quickshell UI is embedded into the `dms` binary at build time. `make build` copies `quickshell/` into `core/internal/shellembed/dist/` (generated, never committed) and compiles with the `withshell` tag. `make dev` builds without the tag — that binary carries no UI and requires an explicit config dir.

```bash
make build   # embedded binary at core/bin/dms
make dev     # untagged development build
make run     # dev build, then launch against the live quickshell/ tree
```

The UI config dir resolves in order: `-c <dir>`, `DMS_SHELL_DIR`, the dir a running instance is using, then the embedded UI. Each candidate must contain `shell.qml`. `make run` uses `-c $(pwd)/quickshell`, so QML edits hot-reload from the working tree.

The Go core depends on [dankgo](https://github.com/duxlabs-dev/dux-go) for logging, XDG paths, the IPC transport, and the quickshell process lifecycle. To develop against a local dankgo checkout, create a gitignored `go.work` at the repo root:

```
go work init ./core ../dankgo
```

## Shared widgets (dux-qml-common)

Everything under `quickshell/DCommon/` (core widgets, the file browser, scroll physics, bundled fonts) is shared across the DMS suite and lives in the `dux-qml-common` submodule. It is a normal git worktree:

1. Edit files under `dux-qml-common/` (or through the `quickshell/DCommon` symlink — same files) and test in the running shell; hot reload works as usual. For isolated widget work, the library is its own runnable config with a gallery: `qs -c dux-qml-common`.
2. Commit and PR those changes in the `dux-qml-common` repo: `cd dux-qml-common && git switch -c my-change`, push, open the PR there.
3. Once merged, bump the pointer here: `make update-common` (updates the submodule and the nix flake input together), then commit alongside any DMS-side changes. If you only bump the submodule, CI syncs `flake.lock` to it automatically on master.

The submodule URL in `.gitmodules` is HTTPS so CI and anonymous clones keep working. To push over SSH instead of being prompted for credentials, add a push rewrite to your git config — fetches stay HTTPS, pushes use SSH:

```bash
git config --global url."git@github.com:duxlabs-dev/".pushInsteadOf "https://github.com/duxlabs-dev/"
```

Shared widgets read app-provided singletons (`Theme`, `SettingsData`, ...) through a documented contract — see the dux-qml-common README. If your change needs a new contract property, add it to the library's stub singletons in the same PR, then to `quickshell/Common/` here when you bump.

Files in `quickshell/Widgets/`, `quickshell/Common/`, and `quickshell/Modals/FileBrowser/` that moved to the library remain in place as thin wrappers, so existing `qs.Widgets`, `qs.Common`, and `qs.Modals.FileBrowser` imports keep working for the shell and for plugins. The `Dank*` widget names are deprecated: each one logs a warning naming its replacement. New code imports `qs.DCommon.Widgets` and uses the `D*` names (`DButton`, `DIcon`, `DListView`, and so on).

## VSCode Setup

This is a monorepo, the easiest thing to do is to open an editor in either `quickshell`, `core`, or both depending on which part of the project you are working on.

### QML (`quickshell` directory)

1. Install the [QML Extension](https://doc.qt.io/vscodeext/)
2. Configure `ctrl+shift+p` -> user preferences (json) with qmlls path

**Note:** Paths may vary by distribution. Below are examples for Arch Linux and Fedora.

**Arch Linux:**

```json
{
  "[qml]": {
    "editor.defaultFormatter": "qt-project.qmlls",
    "editor.formatOnSave": true
  },
  "qt-qml.doNotAskForQmllsDownload": true,
  "qt-qml.qmlls.customExePath": "/usr/lib/qt6/bin/qmlls",
  "qt-core.additionalQtPaths": [
    {
      "name": "Qt-6.x-linux-g++",
      "path": "/usr/bin/qmake"
    }
  ]
}
```

**Fedora:**

```json
{
  "[qml]": {
    "editor.defaultFormatter": "qt-project.qmlls",
    "editor.formatOnSave": true
  },
  "qt-qml.doNotAskForQmllsDownload": true,
  "qt-qml.qmlls.customExePath": "/usr/bin/qmlls",
  "qt-core.additionalQtPaths": [
    {
      "name": "Qt-6.x-Fedora-linux-g++",
      "path": "/usr/bin/qmake6"
    }
  ]
}
```

3. Create empty `.qmlls.ini` file in `quickshell/` directory

```bash
cd quickshell
touch .qmlls.ini
```

4. Restart dms to generate the `.qmlls.ini` file

5. Run `make lint-qml` from the repo root to lint QML entrypoints (requires the `.qmlls.ini` generated above). The script needs the **Qt 6** `qmllint`; it checks `qmllint6`, Fedora's `qmllint-qt6`, `/usr/lib/qt6/bin/qmllint`, then `qmllint` in `PATH`. If your Qt 6 binary lives elsewhere, set `QMLLINT=/path/to/qmllint`.

6. Run `make test-qml` for QML unit tests (`nix develop --command make test-qml` with Nix). These use Qt 6 `qmltestrunner` offscreen and do not require a running shell. Set `QMLTESTRUNNER=/path/to/qmltestrunner` if needed.

7. Make your changes, test, and open a pull request.

### I18n/Localization

When adding user-facing strings, ensure they are wrapped in `I18n.tr()` with context, for example.

```qml
import qs.Common

Text {
  text: I18n.tr("Hello World", "<This is context for the translators, example> Hello world greeting that appears on the lock screen")
}
```

Preferably, try to keep new terms to a minimum and re-use existing terms where possible. See `quickshell/translations/en.json` for the list of existing terms. (This isn't always possible obviously, but instead of using `Auto-connect` you would use `Autoconnect` since it's already translated)

Don't re-extract the translations. `en.json` and `template.json` are synced with POEditor by a maintainer script, so running `extract_translations.py` in your PR just makes a diff that fights the next sync. Add your `I18n.tr()` calls and leave the catalogs alone. (`settings_search_index.json` is the exception, the pre-commit hook regenerates that one when you touch settings QML.)

Strings inside `quickshell/DCommon/` are owned by the dux-qml-common repo but stay in the DMS POEditor project — extraction here deliberately skips them, and `scripts/i18nsync.py sync` uploads the union of app terms and the submodule's terms instead (common terms carry the `dux-qml-common` tag). On download the sync splits the exports: app translations go to `quickshell/translations/poexports/`, common translations go to `dux-qml-common/DCommon/translations/poexports/` for you to commit in that repo and bump. At runtime `I18n` merges both catalogs (app terms win). Other apps (dankcalendar) keep their own POEditor projects and merge the `dux-qml-common`-tagged terms from the DMS project.

### GO (`core` directory)

1. Install the [Go Extension](https://code.visualstudio.com/docs/languages/go)
2. Ensure code is formatted with `make fmt`
3. Add appropriate test coverage and ensure tests pass with `make test`
4. Run `go mod tidy`
5. Open pull request

golangci-lint runs as a pre-commit hook and covers `go vet`, so there's nothing separate to run. If you run `go vet ./...` yourself you'll see complaints about the generated mocks, ignore them, `core/.golangci.yml` excludes that directory.

#### Mocks

Test mocks under `core/internal/mocks/` are generated with [mockery](https://vektra.github.io/mockery/) v3. Don't edit them by hand, regenerate after changing a mocked interface:

```bash
cd core
go run github.com/vektra/mockery/v3@latest
# or with it installed (go install github.com/vektra/mockery/v3@latest):
mockery
```

`core/.mockery.yml` lists every mocked interface and where its mock goes (e.g. `network.Backend` -> `internal/mocks/network/mock_Backend.go`). To mock a new interface, add it there under its package and regenerate.

## Generative AI

Using an LLM to help write code is fine. Submitting its output unread is not.

- You are responsible for every line you submit. You have read it, tested it, and can explain it in review.
- Say in the PR when a meaningful part of the code was AI generated.
- Write PR descriptions, issues, and comments yourself. No AI-written or AI-rewritten text. A few plain sentences in your own words beat a page of generated summary. PRs and issues with AI-written text get closed without review.
  - You can use AI to troubleshoot, gather data, and information for new issues. The description should be written by a human.
  - If you are not an english-native speaker you can use AI to translate your request or PR description
- Do not file issues or leave comments you have not verified yourself. Reports that do not reproduce get closed.
- PRs that read like unreviewed output, with narrating comments, invented APIs, or style that ignores the file they are in, get closed without review.

## Pull request

Include screenshots/video if applicable in your pull request if applicable, to visualize what your change is affecting.
