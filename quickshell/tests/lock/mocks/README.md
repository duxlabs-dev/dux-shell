# Quickshell test doubles

`make test-qml` adds this directory to the Qt import path so QtTest can load the
production `Modules/Lock/Pam.qml` without a running Quickshell session or invoking
real PAM authentication. These modules are test-only; the shell never imports
this directory.

`PamContext` models start/abort/completion and records attempts. Tests explicitly
supply completion results; Qt timers and QML bindings run normally. File and
process doubles do no I/O; a `FileView` is loaded unless its path is empty or
listed in `MockFiles.missing`. These tests cover authentication flow control, not
PAM policy enforcement, daemon behavior, or fingerprint hardware.
