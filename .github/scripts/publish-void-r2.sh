#!/usr/bin/env bash
# Shared by dux-shell and dux-repo, which both write dms/current; keep both copies identical.
# ETag guard: publish aborts if another writer replaced x86_64-repodata mid-run.

set -euo pipefail

usage() {
    echo "usage: $0 download|is-indexed|index|publish" >&2
    exit 2
}

require_env() {
    local name
    for name in "$@"; do
        if [[ -z "${!name:-}" ]]; then
            echo "error: $name is required" >&2
            exit 2
        fi
    done
}

require_env R2_BUCKET R2_ENDPOINT R2_PREFIX REPOSITORY_DIR

REPODATA_KEY="${R2_PREFIX}/current/x86_64-repodata"
ETAG_STATE="$REPOSITORY_DIR/.repodata-etag"

aws_r2() {
    aws --endpoint-url "$R2_ENDPOINT" "$@"
}

# Print the remote repodata ETag, or "none" when the object does not exist yet.
remote_repodata_etag() {
    local out
    if out="$(aws_r2 s3api head-object --bucket "$R2_BUCKET" --key "$REPODATA_KEY" \
        --query ETag --output text 2>&1)"; then
        printf '%s\n' "$out"
    elif grep -qiE 'Not Found|404' <<<"$out"; then
        echo none
    else
        printf '%s\n' "$out" >&2
        return 1
    fi
}

record_repodata_etag() {
    remote_repodata_etag > "$ETAG_STATE"
}

# Abort when another publisher replaced the index since we recorded it.
assert_repodata_unchanged() {
    local stage="$1" expected actual
    if [[ ! -s "$ETAG_STATE" ]]; then
        echo "error: $ETAG_STATE is missing; run '$0 download' before publishing" >&2
        exit 1
    fi
    expected="$(<"$ETAG_STATE")"
    actual="$(remote_repodata_etag)"
    if [[ "$expected" != "$actual" ]]; then
        echo "error: ${REPODATA_KEY} changed while this run was building ($stage)" >&2
        echo "  recorded ETag: $expected" >&2
        echo "  current ETag:  $actual" >&2
        echo "another publisher won the race; nothing was overwritten. Re-run to retry." >&2
        exit 1
    fi
}

download() {
    mkdir -p "$REPOSITORY_DIR/current" "$REPOSITORY_DIR/previous-current"

    # ETag must be taken before the sync so a mid-sync publish is detected.
    record_repodata_etag
    aws_r2 s3 sync \
        "s3://${R2_BUCKET}/${R2_PREFIX}/current/" \
        "$REPOSITORY_DIR/current/" \
        --only-show-errors

    cp -a "$REPOSITORY_DIR/current/." "$REPOSITORY_DIR/previous-current/"
}

# Staged pkgvers count as indexed too.
indexed_pkgvers() {
    local repodata="$REPOSITORY_DIR/current/x86_64-repodata" member
    [[ -s "$repodata" ]] || return 0
    for member in index.plist stage.plist; do
        tar -xOf "$repodata" "$member" 2>/dev/null | python3 -c '
import plistlib, sys
data = sys.stdin.buffer.read()
for pkg in (plistlib.loads(data).values() if data.strip() else ()):
    print(pkg["pkgver"])
' || true
    done
}

# Also catches packages uploaded by a run that died before its repodata PUT.
is_indexed() {
    local known file
    shopt -s nullglob
    known="$(indexed_pkgvers)"
    for file in "$REPOSITORY_DIR"/current/*.xbps; do
        if ! grep -qxF "$(xbps-uhelper binpkgver "$(basename "$file")")" <<<"$known"; then
            echo "$(basename "$file") is not in ${R2_PREFIX}/current/x86_64-repodata"
            return 1
        fi
    done
}

index() {
    require_env XBPS_PRIVATE_KEY
    local dir="$REPOSITORY_DIR/current" sig

    shopt -s nullglob
    local pkgs=("$dir"/*.xbps)
    if (( ${#pkgs[@]} == 0 )); then
        echo "error: no .xbps files to index in $dir" >&2
        exit 1
    fi

    rm -f "$dir"/*.sig
    xbps-rindex -a "${pkgs[@]}"
    xbps-rindex --remove-obsoletes "$dir"

    # Unchanged packages keep their .sig2 byte-for-byte; drop those of removed packages.
    for sig in "$dir"/*.sig2; do
        [[ -f "${sig%.sig2}" ]] || rm -f "$sig"
    done

    XBPS_KEY_FILE="$(mktemp)"
    trap 'rm -f "$XBPS_KEY_FILE"' EXIT
    printf '%s\n' "$XBPS_PRIVATE_KEY" > "$XBPS_KEY_FILE"
    xbps-rindex --sign --signedby "AvengeMedia <AvengeMedia.US@gmail.com>" --privkey "$XBPS_KEY_FILE" "$dir"
    xbps-rindex --sign-pkg --privkey "$XBPS_KEY_FILE" "$dir"/*.xbps
}

build_manifest() {
    local packages='[]' previous_sources='{}'
    local file filename pkgver name version revision sha size

    for file in "$REPOSITORY_DIR"/current/*.xbps; do
        filename="$(basename "$file")"
        pkgver="$(xbps-uhelper binpkgver "$filename")"
        name="$(xbps-uhelper getpkgname "$pkgver")"
        version="$(xbps-uhelper getpkgversion "$pkgver")"
        revision="$(xbps-uhelper getpkgrevision "$pkgver")"
        version="${version%_"${revision}"}"
        sha="$(sha256sum "$file" | cut -d' ' -f1)"
        size="$(stat -c '%s' "$file")"
        packages="$(jq \
            --arg name "$name" \
            --arg version "$version" \
            --arg revision "$revision" \
            --arg filename "$filename" \
            --arg sha256 "$sha" \
            --argjson size "$size" \
            '. + [{name: $name, version: $version, revision: $revision, filename: $filename, sha256: $sha256, size: $size}]' \
            <<<"$packages")"
    done

    # `sources` maps publishing repo -> last published commit; `source_commit` kept for older consumers.
    if [[ -s "$REPOSITORY_DIR/previous-current/manifest.json" ]]; then
        previous_sources="$(jq -c '.sources // {}' "$REPOSITORY_DIR/previous-current/manifest.json" 2>/dev/null || echo '{}')"
    fi

    jq -n \
        --arg repository "$R2_PREFIX" \
        --arg source_repository "$SOURCE_REPOSITORY" \
        --arg source_commit "$SOURCE_COMMIT" \
        --arg published_at "$PUBLISHED_AT" \
        --argjson previous_sources "$previous_sources" \
        --argjson packages "$packages" \
        '{schema: 1, repository: $repository, source_repository: $source_repository, source_commit: $source_commit,
          sources: ($previous_sources + {($source_repository): $source_commit}),
          published_at: $published_at, packages: $packages}' \
        > "$REPOSITORY_DIR/current/manifest.json"
}

verify_immutable_packages() {
    local file previous

    for file in "$REPOSITORY_DIR"/current/*.xbps "$REPOSITORY_DIR"/current/*.sig2; do
        previous="$REPOSITORY_DIR/previous-current/$(basename "$file")"
        if [[ -f "$previous" ]] && ! cmp -s "$previous" "$file"; then
            echo "error: refusing to replace immutable object $(basename "$file")" >&2
            echo "bump the XBPS revision or version before publishing a changed build" >&2
            exit 1
        fi
    done
}

archive_retired() {
    local old filename
    local archive_prefix="archive/${R2_PREFIX}/${PUBLISHED_AT//:/-}"

    shopt -s nullglob
    for old in "$REPOSITORY_DIR"/previous-current/*.xbps "$REPOSITORY_DIR"/previous-current/*.sig2; do
        filename="$(basename "$old")"
        if [[ ! -e "$REPOSITORY_DIR/current/$filename" ]]; then
            aws_r2 s3 cp \
                "$old" \
                "s3://${R2_BUCKET}/${archive_prefix}/${filename}" \
                --cache-control 'private,no-store' \
                --only-show-errors
        fi
    done
}

upload_current() {
    local file filename old

    # Versioned package objects must exist before repodata can reference them.
    for file in "$REPOSITORY_DIR"/current/*.xbps "$REPOSITORY_DIR"/current/*.sig2; do
        filename="$(basename "$file")"
        aws_r2 s3 cp \
            "$file" \
            "s3://${R2_BUCKET}/${R2_PREFIX}/current/${filename}" \
            --cache-control 'public,max-age=31536000,immutable' \
            --only-show-errors
    done

    # Orphaned .xbps from an aborted run are re-indexed by the next run.
    assert_repodata_unchanged "before uploading repodata"

    # Keep the ETag of our own PUT for the final check.
    aws_r2 s3api put-object \
        --bucket "$R2_BUCKET" \
        --key "$REPODATA_KEY" \
        --body "$REPOSITORY_DIR/current/x86_64-repodata" \
        --cache-control 'no-cache' \
        --query ETag --output text > "$ETAG_STATE"

    # The manifest is the publication marker and is always uploaded last.
    aws_r2 s3 cp \
        "$REPOSITORY_DIR/current/manifest.json" \
        "s3://${R2_BUCKET}/${R2_PREFIX}/current/manifest.json" \
        --cache-control 'no-cache' \
        --only-show-errors

    # Remove retired objects only if the live index is still ours.
    assert_repodata_unchanged "before removing retired objects"
    shopt -s nullglob
    for old in "$REPOSITORY_DIR"/previous-current/*; do
        filename="$(basename "$old")"
        if [[ ! -e "$REPOSITORY_DIR/current/$filename" ]]; then
            aws_r2 s3 rm \
                "s3://${R2_BUCKET}/${R2_PREFIX}/current/${filename}" \
                --only-show-errors
        fi
    done
}

publish() {
    require_env SOURCE_COMMIT
    SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-${GITHUB_REPOSITORY:-unknown}}"
    PUBLISHED_AT="${PUBLISHED_AT:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}"
    export PUBLISHED_AT SOURCE_REPOSITORY

    shopt -s nullglob
    local packages=("$REPOSITORY_DIR"/current/*.xbps)
    if (( ${#packages[@]} == 0 )); then
        echo "error: refusing to publish an empty XBPS repository" >&2
        exit 1
    fi
    [[ -s "$REPOSITORY_DIR/current/x86_64-repodata" ]] || {
        echo "error: x86_64-repodata is missing or empty" >&2
        exit 1
    }
    for file in "${packages[@]}"; do
        [[ -s "${file}.sig2" ]] || {
            echo "error: signature is missing for $(basename "$file")" >&2
            exit 1
        }
    done

    assert_repodata_unchanged "before publishing"
    verify_immutable_packages
    build_manifest
    archive_retired
    upload_current
}

case "${1:-}" in
    download) download ;;
    is-indexed) is_indexed ;;
    index) index ;;
    publish) publish ;;
    *) usage ;;
esac
