#!/usr/bin/env bash
# Build a DMS per-series upload plan by comparing Git/GitHub with Launchpad.

set -euo pipefail

PPA_OWNER="${PPA_OWNER:-duxlabs}"
LAUNCHPAD_API="https://api.launchpad.net/1.0"
SERIES_LIST=(resolute stonking)
PACKAGE_FILTER="dms-git"
REBUILD_RELEASE=""
JSON=false

PACKAGES=(
    "dms:dms:release"
    "dms-git:dms-git:git"
)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package)
            PACKAGE_FILTER="$2"
            shift 2
            ;;
        --rebuild)
            REBUILD_RELEASE="$2"
            shift 2
            ;;
        --json)
            JSON=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

latest_tag() {
    git ls-remote --tags --refs --sort='-v:refname' https://github.com/duxlabs-dev/dux-shell.git |
        sed -n '1s|.*/v\{0,1\}||p'
}

published_version() {
    local package="$1"
    local ppa="$2"
    local series="$3"
    local series_url="https%3A%2F%2Fapi.launchpad.net%2F1.0%2Fubuntu%2F${series}"
    local url="${LAUNCHPAD_API}/~${PPA_OWNER}/+archive/ubuntu/${ppa}?ws.op=getPublishedSources&source_name=${package}&status=Published&distro_series=${series_url}"

    curl -fsSL "$url" 2>/dev/null | jq -r '.entries[0].source_package_version // empty'
}

release_base() {
    echo "$1" | sed -E 's/ppa[0-9]+$//' | sed -E 's/-[0-9]+$//'
}

ppa_suffix() {
    local version="$1"
    if [[ "$version" =~ ppa([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

embedded_commit() {
    echo "$1" | sed -nE 's/.*[+~]git[0-9]+\.([a-f0-9]{7,12}).*/\1/p'
}

target_ppa() {
    local series="$1"
    if [[ -n "$REBUILD_RELEASE" ]]; then
        if [[ "$series" == "stonking" ]]; then
            echo $((REBUILD_RELEASE + 1))
        else
            echo "$REBUILD_RELEASE"
        fi
    elif [[ "$series" == "stonking" ]]; then
        echo "2"
    else
        echo "1"
    fi
}

rebuild_release_is_newer() {
    local series="$1"
    local published="$2"
    local requested current

    [[ -n "$REBUILD_RELEASE" ]] || return 1

    requested="$(target_ppa "$series")"
    current="$(ppa_suffix "$published")"
    [[ "$requested" -gt "$current" ]]
}

include_package() {
    local package="$1"
    [[ "$PACKAGE_FILTER" == "all" || "$PACKAGE_FILTER" == "$package" ]]
}

CURRENT_COMMIT="$(git rev-parse HEAD)"
LATEST_TAG=""
TARGETS=()

for pkg_info in "${PACKAGES[@]}"; do
    IFS=':' read -r package ppa type <<< "$pkg_info"
    include_package "$package" || continue

    for series in "${SERIES_LIST[@]}"; do
        ppa_version="$(published_version "$package" "$ppa" "$series")"
        needs_update=false
        reason=""

        if [[ -z "$ppa_version" ]]; then
            needs_update=true
            reason="missing from ${series}"
        elif [[ "$type" == "git" ]]; then
            ppa_commit="$(embedded_commit "$ppa_version")"
            if [[ -z "$ppa_commit" || "${CURRENT_COMMIT:0:${#ppa_commit}}" != "$ppa_commit" ]]; then
                needs_update=true
                reason="commit ${ppa_commit:-none} -> ${CURRENT_COMMIT:0:9}"
            fi
        else
            if [[ -z "$LATEST_TAG" ]]; then
                LATEST_TAG="$(latest_tag)"
            fi
            ppa_base="$(release_base "$ppa_version")"
            if [[ "$ppa_base" != "$LATEST_TAG" ]]; then
                needs_update=true
                reason="version ${ppa_base:-none} -> ${LATEST_TAG}"
            fi
        fi

        if [[ "$needs_update" != "true" ]] && rebuild_release_is_newer "$series" "$ppa_version"; then
            needs_update=true
            reason="rebuild ppa$(ppa_suffix "$ppa_version") -> ppa$(target_ppa "$series")"
        fi

        if [[ "$needs_update" == "true" ]]; then
            target="${package}:${series}:$(target_ppa "$series")"
            TARGETS+=("$target")
            echo "${package}/${series}: ${reason} (published: ${ppa_version:-none})" >&2
        else
            echo "${package}/${series}: current (${ppa_version})" >&2
        fi
    done
done

if [[ "$JSON" == "true" ]]; then
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${TARGETS[@]}" | jq -R -s -c 'split("\n")[:-1]'
    fi
else
    echo "${TARGETS[*]}"
fi
