# Shell tests

`make test-qml` runs three suites: `logic` (the `*.test.mjs` files here under `node --test`), `qt` (`qmltestrunner` over `unit/`) and `lock` (`qmltestrunner` over `lock/` with the mocks in `lock/mocks`). It needs Python 3, Node.js, Lua, make and the Qt 6 `qmltestrunner`. The Nix development shell includes them.

The `qml-tests` pre-commit hook runs the same suites when shell code, tests or their configuration changes. CI runs that hook in the QML tests job.

```sh
prek run qml-tests --all-files
python3 quickshell/tests/run-qml.py logic
python3 quickshell/tests/run-qml.py qt
python3 quickshell/tests/run-qml.py lock
```

Set `QMLTESTRUNNER` to override the Qt 6 executable.

## Writing a test

- A test exercises a `.js` module, a function of a `Services/` or `Common/` singleton, or an IPC handler. Nothing under `Modules/`, `Modals/` or `Widgets/` is read, sliced or mocked. Those files change with every UI tweak, and tests over them only ever failed on the tweak.
- No compositor, display server, running shell, timers or waits. Each suite finishes in well under a second.
- A test must fail on the broken code. No defaults, no tables asserted against a copy of themselves, no "it instantiates".
- When a test slices QML source, the mock has to honour the arguments the function passes. A mock that ignores them passes on the old code and fails on an equivalent rewrite.
