#!/usr/bin/env bash
# Report master commits missing from a release branch.
#
# Usage: port-audit.sh [<target-branch>] [--issue]
#
# Target defaults to the newest origin/stable-* branch. --issue writes the
# report to the "Port status: <target>" tracking issue body (needs gh auth).
set -euo pipefail

TARGET=""
UPDATE_ISSUE=0
for arg in "$@"; do
  case "$arg" in
    --issue) UPDATE_ISSUE=1 ;;
    *) TARGET="$arg" ;;
  esac
done

git fetch origin --prune --quiet 2>/dev/null || true

if [ -z "$TARGET" ]; then
  TARGET=$(git branch -r --list 'origin/stable-*' --format='%(refname:short)' |
    sed 's|^origin/||' | sort -V | tail -1)
  [ -n "$TARGET" ] || { echo "error: no origin/stable-* branch found" >&2; exit 1; }
fi
git rev-parse --verify "origin/${TARGET}" >/dev/null 2>&1 ||
  { echo "error: branch origin/${TARGET} not found" >&2; exit 1; }

BASE=$(git merge-base "origin/${TARGET}" origin/master)

# shas already ported via cherry-pick -x trailers
declare -A PORTED
while read -r sha; do
  [ -n "$sha" ] && PORTED[$sha]=1
done < <(git log --format=%B "${BASE}..origin/${TARGET}" 2>/dev/null |
  grep -oE 'cherry picked from commit [0-9a-f]{40}' | awk '{print $5}')

# git cherry: "+ sha" = not on target (by patch-id), "- sha" = equivalent exists
port_shas=()
other_shas=()
fixes=""
others=""
flagged=""
fix_count=0
other_count=0
flagged_count=0
VER="${TARGET#stable-}"
FLAG_RE="\\bport[-: /]+(stable-)?${VER//./\\.}\\b"
while read -r mark sha; do
  [ "$mark" = "+" ] || continue
  [ -n "${PORTED[$sha]:-}" ] && continue
  subject=$(git log -1 --format=%s "$sha")
  # skip automated bumps/CI commits
  author=$(git log -1 --format=%an "$sha")
  case "$author" in *"[bot]"*) continue ;; esac
  short=$(git rev-parse --short "$sha")
  pr=$(grep -oE '#[0-9]+' <<<"$subject" | head -1 || true)
  line="- [ ] \`${short}\` ${subject} (${author}${pr:+, ${pr}})"
  # explicit "port X.Y" mention anywhere in the message = strongest signal
  if git log -1 --format=%B "$sha" | grep -qiE "$FLAG_RE"; then
    flagged+="${line}"$'\n'
    flagged_count=$((flagged_count + 1))
    port_shas+=("$short")
  elif grep -qiE '^(fix|hotfix|bugfix)([(:! ]|$)|^[a-z0-9_./-]+: *fix' <<<"$subject"; then
    fixes+="${line}"$'\n'
    fix_count=$((fix_count + 1))
    port_shas+=("$short")
  else
    others+="${line}"$'\n'
    other_shas+=("$short")
    other_count=$((other_count + 1))
  fi
done < <(git cherry "origin/${TARGET}" origin/master "$BASE")

FLAGGED_SECTION=""
if [ "$flagged_count" -gt 0 ]; then
  FLAGGED_SECTION="### :warning: Flagged \"port ${VER}\" but not applied (${flagged_count})"$'\n\n'"${flagged}"
fi

PORT_FIXES=""
PORT_ALL=""
[ "${#port_shas[@]}" -gt 0 ] && PORT_FIXES="scripts/port.sh ${TARGET} ${port_shas[*]}"
all_shas=("${port_shas[@]}" "${other_shas[@]}")
[ "${#other_shas[@]}" -gt 0 ] && PORT_ALL="scripts/port.sh ${TARGET} ${all_shas[*]}"

PORT_COMMAND=""
if [ -n "$PORT_FIXES" ]; then
  PORT_COMMAND+=$'\n### Port fixes\n\n```sh\n'"${PORT_FIXES}"$'\n```\n'
fi
if [ -n "$PORT_ALL" ]; then
  PORT_COMMAND+=$'\n### Port fixes and other candidates\n\n```sh\n'"${PORT_ALL}"$'\n```\n'
fi

REPORT=$(cat <<EOF
## Port audit: \`${TARGET}\` vs \`master\`

Base: \`$(git rev-parse --short "$BASE")\` · generated $(date -u +%Y-%m-%dT%H:%MZ)

${FLAGGED_SECTION}
### Candidate fixes not ported (${fix_count})

${fixes:-_none — all caught up_ }

<details><summary>Other possible candidates (${other_count})</summary>

${others:-none}

</details>
${PORT_COMMAND}
EOF
)

# shellcheck disable=SC2016 # backticks are literal markdown
plain() { sed 's/^- \[ \] `\([0-9a-f]*\)`/  \1 /' <<<"$1"; }

# markdown is for the step summary, the tracking issue, and pipes; terminals get plain text
if [ -t 1 ]; then
  echo "Port audit: ${TARGET} vs master (base $(git rev-parse --short "$BASE"))"
  if [ "$flagged_count" -gt 0 ]; then
    printf '\nFlagged "port %s" but not applied (%s):\n%s\n' "$VER" "$flagged_count" "$(plain "$flagged")"
  fi
  printf '\nCandidate fixes not ported (%s):\n%s\n' "$fix_count" "$(plain "${fixes:-  none - all caught up}")"
  printf '\nOther possible candidates (%s):\n%s\n' "$other_count" "$(plain "${others:-  none}")"
  [ -n "$PORT_FIXES" ] && printf '\nPort fixes:\n  %s\n' "$PORT_FIXES"
  [ -n "$PORT_ALL" ] && printf '\nPort fixes and other candidates:\n  %s\n' "$PORT_ALL"
else
  echo "$REPORT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$REPORT" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$UPDATE_ISSUE" = 1 ]; then
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
  TITLE="Port status: ${TARGET}"
  num=$(gh issue list --repo "$REPO" --state open --limit 1000 \
    --json number,title --jq "map(select(.title == \"${TITLE}\")) | .[0].number // empty")
  if [ -z "$num" ]; then
    num=$(gh issue create --repo "$REPO" --title "$TITLE" --body "$REPORT" | grep -oE '[0-9]+$')
    echo "created tracking issue #${num}" >&2
  else
    gh issue edit "$num" --repo "$REPO" --body "$REPORT" >/dev/null
    echo "updated tracking issue #${num}" >&2
  fi
fi
