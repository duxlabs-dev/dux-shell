#!/usr/bin/env bash
# Port (cherry-pick -x) commits onto a release branch.
#
# Usage: port.sh <target-branch> <sha> [<sha>...]
#
# Already-ported commits are skipped. Conflicts get a port/<sha>-<ver>
# branch and a comment on the "Port status: <target>" tracking issue.
#
# Requires: full-history checkout, git identity, push access, gh auth.
# Env: PORT_SOURCE_PR - source PR number (optional, for reporting)
set -euo pipefail

TARGET="${1:?usage: port.sh <target-branch> <sha> [<sha>...]}"
shift
[ "$#" -ge 1 ] || { echo "error: no commits given" >&2; exit 1; }

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
TRACKING_TITLE="Port status: ${TARGET}"

log() { echo "[port] $*" >&2; }

# a global submodule.recurse breaks cherry-pick --abort in the uninitialised worktree
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=submodule.recurse GIT_CONFIG_VALUE_0=false

git fetch origin "refs/heads/${TARGET}:refs/remotes/origin/${TARGET}" --quiet ||
  { echo "error: branch origin/${TARGET} not found" >&2; exit 1; }

TRACKING_ISSUE=""
tracking_issue() {
  [ -n "$TRACKING_ISSUE" ] && return
  local num
  # --search lags behind just-created issues and caused duplicates
  num=$(gh issue list --repo "$REPO" --state open --limit 1000 \
    --json number,title --jq "map(select(.title == \"${TRACKING_TITLE}\")) | .[0].number // empty")
  if [ -z "$num" ]; then
    num=$(gh issue create --repo "$REPO" --title "${TRACKING_TITLE}" \
      --body "Maintainer tracking issue for ports to \`${TARGET}\`. The port audit updates this body; the port engine reports conflicts as comments." \
      | grep -oE '[0-9]+$')
  fi
  TRACKING_ISSUE="$num"
}

already_ported() {
  local sha="$1"
  if git log "origin/${TARGET}" --grep="cherry picked from commit ${sha}" --format=%H | grep -q .; then
    return 0
  fi
  # git cherry prints "- <sha>" when a patch-equivalent commit exists upstream
  if git cherry "origin/${TARGET}" "$sha" "${sha}~1" 2>/dev/null | grep -q "^- "; then
    return 0
  fi
  return 1
}

report_conflict() {
  local sha="$1" short subject branch issue
  short=$(git rev-parse --short "$sha")
  subject=$(git log -1 --format=%s "$sha")
  local ver="${TARGET#stable-}"
  branch="port/${short}-${ver}"
  git push origin "refs/remotes/origin/${TARGET}:refs/heads/${branch}" 2>/dev/null ||
    log "conflict branch ${branch} already exists"
  tracking_issue
  issue="$TRACKING_ISSUE"
  gh issue comment "$issue" --repo "$REPO" --body "$(cat <<EOF
:warning: **Conflict** porting \`${short}\` — ${subject}${PORT_SOURCE_PR:+ (from #${PORT_SOURCE_PR})} — to \`${TARGET}\`.

Resolve locally:
\`\`\`bash
git fetch origin
git switch ${branch}
git cherry-pick -x ${sha}
# resolve conflicts, git cherry-pick --continue, then:
git push origin ${branch}:${TARGET}
git push origin --delete ${branch}
\`\`\`
EOF
)"
  log "conflict on ${short} reported to issue #${issue}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo ":warning: conflict porting \`${short}\` (${subject}) to \`${TARGET}\` — see tracking issue #${issue}" >> "$GITHUB_STEP_SUMMARY"
  fi
}

WORK="_port_worktree_$$"
git worktree add --detach "$WORK" "origin/${TARGET}" >/dev/null
trap 'cd "${OLDPWD:-.}" 2>/dev/null; git worktree remove --force "$WORK" 2>/dev/null || true' EXIT
cd "$WORK"

shas=()
for ref in "$@"; do
  sha=$(git rev-parse --verify "${ref}^{commit}") || { log "skip ${ref}: not a commit"; continue; }
  shas+=("$sha")
done
[ "${#shas[@]}" -gt 0 ] || exit 0
# pick in history order so a commit lands after the ones it builds on
mapfile -t shas < <(git rev-list --no-walk --reverse "${shas[@]}")

picked=0
for sha in "${shas[@]}"; do
  short=$(git rev-parse --short "$sha")

  if already_ported "$sha"; then
    log "skip ${short}: already on ${TARGET}"
    continue
  fi

  pick_args=(-x)
  # PR merge commits need the mainline parent
  if [ "$(git rev-list --no-walk --count --min-parents=2 "$sha")" -gt 0 ]; then
    pick_args+=(-m 1)
  fi

  if git cherry-pick "${pick_args[@]}" "$sha"; then
    log "picked ${short}"
    picked=$((picked + 1))
  else
    git cherry-pick --abort || { log "could not abort ${short}; stopping"; exit 1; }
    report_conflict "$sha"
  fi
done

if [ "$picked" -gt 0 ]; then
  if ! git push origin "HEAD:refs/heads/${TARGET}"; then
    # another run may have advanced the branch; rebase our picks and retry once
    git fetch origin "refs/heads/${TARGET}:refs/remotes/origin/${TARGET}"
    git rebase "origin/${TARGET}"
    git push origin "HEAD:refs/heads/${TARGET}"
  fi
  log "pushed ${picked} commit(s) to ${TARGET}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo ":white_check_mark: ported ${picked} commit(s) to \`${TARGET}\`" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
