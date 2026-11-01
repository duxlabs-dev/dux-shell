#!/usr/bin/env bash
set -euo pipefail

script_dir="$(
    CDPATH=''
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"
repo_root="$(
    CDPATH=''
    cd -- "${script_dir}/../.." && pwd
)"
quickshell_dir="${repo_root}/quickshell"
qmlls_config="${quickshell_dir}/.qmlls.ini"

# Resolve qmllint: honour QMLLINT, then try common Qt 6 binary names and
# install paths, and finally bare qmllint. We need the Qt 6 build (>= 6.x)
# because older Qt 5 qmllint doesn't understand --ignore-settings / -W.
resolve_qmllint() {
    if [[ -n "${QMLLINT:-}" ]]; then
        printf '%s\n' "${QMLLINT}"
        return
    fi
    local candidate
    for candidate in qmllint6 qmllint-qt6 /usr/lib/qt6/bin/qmllint qmllint; do
        if command -v -- "${candidate}" >/dev/null 2>&1; then
            printf '%s\n' "${candidate}"
            return
        fi
    done
    return 1
}

if ! qmllint_bin="$(resolve_qmllint)"; then
    printf 'error: qmllint (Qt 6) not found in PATH (override with QMLLINT=/path/to/qmllint)\n' >&2
    exit 127
fi

print_broken_qmlls_link() {
    local target=""
    target="$(readlink -- "${qmlls_config}" 2>/dev/null || true)"
    printf 'error: %s is a broken symlink. lint-qml requires a live Quickshell tooling VFS.\n' "${qmlls_config}" >&2
    if [[ -n "${target}" ]]; then
        printf 'Broken target: %s\n' "${target}" >&2
    fi
    print_vfs_recovery
}

trim_ini_value() {
    local value="$1"
    value="${value#\"}"
    value="${value%\"}"
    printf '%s\n' "${value}"
}

read_ini_value() {
    local key="$1"
    local file="$2"
    local raw

    raw="$(sed -n "s/^${key}=//p" "${file}" | head -n 1)"
    if [[ -z "${raw}" ]]; then
        return 1
    fi

    trim_ini_value "${raw}"
}

print_vfs_recovery() {
    printf 'Quickshell fills the VFS config in itself, but only into a file that already\n' >&2
    printf 'exists; it never creates one. The nix develop shell touches it for you, so\n' >&2
    printf 'outside that shell you have to create it yourself. The VFS also lives under\n' >&2
    printf 'the XDG runtime directory, so a reboot removes it and leaves the file\n' >&2
    printf 'dangling, which makes a plain touch fail. Recreate both with:\n' >&2
    printf '  rm -f %q\n' "${qmlls_config}" >&2
    printf '  touch %q\n' "${qmlls_config}" >&2
    printf '  qs -p %q\n' "${quickshell_dir}" >&2
    printf '  # or: dms -c %q run\n' "${quickshell_dir}" >&2
    printf 'The shell only has to run long enough to write the config, then:\n' >&2
    printf '  qs kill -p %q\n' "${quickshell_dir}" >&2
    printf 'Linting itself does not need a running shell.\n' >&2
}

if [[ -L "${qmlls_config}" && ! -e "${qmlls_config}" ]]; then
    print_broken_qmlls_link
    exit 1
fi

if [[ ! -e "${qmlls_config}" ]]; then
    printf 'error: %s is missing. lint-qml requires the Quickshell tooling VFS.\n' "${qmlls_config}" >&2
    print_vfs_recovery
    exit 1
fi

if ! build_dir="$(read_ini_value "buildDir" "${qmlls_config}")"; then
    printf 'error: %s does not contain a buildDir entry.\n' "${qmlls_config}" >&2
    print_vfs_recovery
    exit 1
fi

if ! import_paths_raw="$(read_ini_value "importPaths" "${qmlls_config}")"; then
    printf 'error: %s does not contain an importPaths entry.\n' "${qmlls_config}" >&2
    print_vfs_recovery
    exit 1
fi

if [[ ! -d "${build_dir}" || ! -f "${build_dir}/qs/qmldir" ]]; then
    printf 'error: Quickshell tooling VFS is missing or stale: %s\n' "${build_dir}" >&2
    print_vfs_recovery
    exit 1
fi

targets=(
    "${quickshell_dir}/shell.qml"
    "${quickshell_dir}/DMSShell.qml"
)

qmllint_args=(
    --ignore-settings
    -W 0
    -I "${build_dir}"
)

IFS=':' read -r -a import_paths <<< "${import_paths_raw}"
for path in "${import_paths[@]}"; do
    if [[ -n "${path}" ]]; then
        qmllint_args+=(-I "${path}")
    fi
done

printf 'lint-qml: checking %d entrypoints with %s\n' "${#targets[@]}" "${qmllint_bin}"

if ! output="$("${qmllint_bin}" "${qmllint_args[@]}" "${targets[@]}" 2>&1)"; then
    printf 'lint-qml: FAIL\n' >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}"
fi

printf 'lint-qml: PASS (%d entrypoints)\n' "${#targets[@]}"
