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

dms_bin="${DMS:-dms}"

# Writes the config and module mirror without launching the shell. Returns 2 when there is no
# dms or its dux-qt-base predates the command, so the checks below fall back to existing files.
write_tooling() {
    command -v -- "${dms_bin}" >/dev/null 2>&1 || return 2
    local output
    output="$("${dms_bin}" qs tooling -p "${quickshell_dir}" 2>&1)" && return 0
    [[ "${output}" == *"not expected: tooling"* ]] && return 2
    printf 'lint-qml: %s qs tooling failed:\n%s\n' "${dms_bin}" "${output}" >&2
    return 1
}

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
    printf 'Update dux-qt-base so "%s qs tooling" can write it, or run the shell from\n' "${dms_bin}" >&2
    printf 'this folder once:\n' >&2
    printf '  rm -f %q && touch %q\n' "${qmlls_config}" "${qmlls_config}" >&2
    printf '  qs -p %q\n' "${quickshell_dir}" >&2
    printf 'then stop it with: qs kill -p %q\n' "${quickshell_dir}" >&2
}

write_tooling || [[ $? -eq 2 ]] || exit 1

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

# --bare keeps the config's import order, so dux-qt-base's Quickshell types (listed first) win
# over an installed upstream copy. UPSTREAM=1 drops them to check against upstream quickshell.
# Their dirs carry a marker file, which catches every spelling of the path.
fork_types=""
upstream_types=""
IFS=':' read -r -a import_paths <<< "${import_paths_raw}"
for path in "${import_paths[@]}"; do
    [[ -n "${path}" ]] || continue
    if [[ -f "${path}/.dux-qt-base" ]]; then
        [[ -n "${UPSTREAM:-}" ]] && continue
        [[ -z "${fork_types}" && -f "${path}/Quickshell/qmldir" ]] && fork_types="${path}"
    elif [[ -z "${upstream_types}" && -f "${path}/Quickshell/qmldir" ]]; then
        upstream_types="${path}"
    fi
    qmllint_args+=(-I "${path}")
done

if [[ -n "${UPSTREAM:-}" ]]; then
    if [[ -z "${upstream_types}" ]]; then
        printf 'error: UPSTREAM=1 needs upstream quickshell on the QML import path.\n' >&2
        exit 1
    fi
else
    qmllint_args+=(--bare)
    if [[ -z "${fork_types}" ]]; then
        printf 'lint-qml: dux-qt-base type info is not installed, using Quickshell types from %s\n' \
            "${upstream_types:-nowhere}" >&2
    fi
fi

printf 'lint-qml: checking %d entrypoints with %s\n' "${#targets[@]}" "${qmllint_bin}"

# The ini already lists the environment's import paths; unset so they can't bypass the filter above.
if ! output="$(env -u QML_IMPORT_PATH -u QML2_IMPORT_PATH "${qmllint_bin}" "${qmllint_args[@]}" "${targets[@]}" 2>&1)"; then
    printf 'lint-qml: FAIL\n' >&2
    printf '%s\n' "${output}" >&2
    exit 1
fi

if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}"
fi

printf 'lint-qml: PASS (%d entrypoints)\n' "${#targets[@]}"
