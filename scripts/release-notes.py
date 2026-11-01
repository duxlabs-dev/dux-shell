#!/usr/bin/env python3
"""Generate release notes and contributor credits from merged PRs.

Attribution comes from GitHub PR data (author login, title, labels) via
`gh api graphql`, falling back to git commit authors for direct pushes.
Ported commits (cherry-pick -x trailers) resolve back to their original
master commit so point releases credit the right PR and author.

Usage:
  release-notes.py v1.4.6..v1.5.0 --format github     # GH release "What's Changed"
  release-notes.py v1.4.6..v1.5.0 --format changelog  # danklinux-docs changelog.mdx entry
  release-notes.py v1.4.6..v1.5.0 --format blog       # MDX contributor tables for danklinux-docs
  release-notes.py v1.4.6..v1.5.0 --format checklist  # flat PR/author review list

Requires: git (full history), gh authenticated. --repo defaults to origin.
"""

import argparse
import json
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

BOT_RE = re.compile(r"\[bot\]$|^github-actions$|^dependabot$", re.I)
# default blog-table exclusions
MAINTAINERS = ["purian23", "bbedward"]
CHERRY_RE = re.compile(r"cherry picked from commit ([0-9a-f]{40})")
PR_REF_RE = re.compile(r"\(#(\d+)\)")

CATEGORIES = OrderedDict([
    ("breaking", "Breaking Changes"),
    ("feature", "Features"),
    ("fix", "Fixes"),
    ("packaging", "Packaging"),
    ("i18n", "Internationalization"),
    ("docs", "Documentation"),
    ("other", "Other Changes"),
])
SUBJECT_HINTS = [
    (re.compile(r"^(feat|add)\b", re.I), "feature"),
    (re.compile(r"^(fix|hotfix|bugfix)", re.I), "fix"),
    (re.compile(r"^[\w./-]+: *fix", re.I), "fix"),
    (re.compile(r"^docs?\b", re.I), "docs"),
    (re.compile(r"^i18n", re.I), "i18n"),
    (re.compile(r"^(distro|packaging|nix|copr|obs|ppa|xbps)", re.I), "packaging"),
]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout


def git_commits(rng):
    """[(sha, author_name, author_email, subject, body)] oldest-first, no merges."""
    sep, rec = "\x00", "\x1e"
    # %x00/%x1e escapes: a literal NUL in argv is invalid
    out = run(["git", "log", "--reverse", "--no-merges",
               "--format=%H%x00%an%x00%ae%x00%s%x00%b%x1e", rng])
    commits = []
    for chunk in out.split(rec):
        chunk = chunk.strip("\n")
        if not chunk:
            continue
        sha, an, ae, subject, body = (chunk.split(sep) + [""] * 5)[:5]
        commits.append((sha, an, ae, subject, body))
    return commits


def fetch_pr_data(repo, shas):
    """{sha: {number, title, url, login, author_url, labels}} via batched GraphQL."""
    owner, name = repo.split("/")
    result = {}
    for i in range(0, len(shas), 50):
        batch = shas[i:i + 50]
        fields = []
        for j, sha in enumerate(batch):
            fields.append(
                f'c{j}: object(oid: "{sha}") {{ ... on Commit {{ '
                f'author {{ user {{ login url }} }} '
                f'associatedPullRequests(first: 1) {{ nodes {{ '
                f'number title url merged author {{ login url }} '
                f'labels(first: 20) {{ nodes {{ name }} }} }} }} }} }}')
        query = (f'query {{ repository(owner: "{owner}", name: "{name}") '
                 f'{{ {" ".join(fields)} }} }}')
        try:
            data = json.loads(run(["gh", "api", "graphql", "-f", f"query={query}"]))
        except subprocess.CalledProcessError as e:
            print(f"warning: GraphQL batch failed: {e.stderr.strip()}", file=sys.stderr)
            continue
        repo_data = data.get("data", {}).get("repository") or {}
        for j, sha in enumerate(batch):
            node = repo_data.get(f"c{j}") or {}
            prs = (node.get("associatedPullRequests") or {}).get("nodes") or []
            pr = next((p for p in prs if p.get("merged")), None)
            commit_user = (node.get("author") or {}).get("user") or {}
            entry = {}
            if pr:
                author = pr.get("author") or {}
                entry = {
                    "number": pr["number"], "title": pr["title"], "url": pr["url"],
                    "login": author.get("login"), "author_url": author.get("url"),
                    "labels": [l["name"] for l in (pr.get("labels") or {}).get("nodes", [])],
                }
            elif commit_user.get("login"):
                entry = {"login": commit_user["login"], "author_url": commit_user.get("url"),
                         "labels": []}
            if entry:
                result[sha] = entry
    return result


INTERNAL_PREFIX_RE = re.compile(
    r"^(?:refactor|chore|ci|build|test|style|perf|imp|revert|cleanup|bump|sync|release)\b", re.I)
FEATURE_CUE_RE = re.compile(
    r"^(?:add(?:s|ed)?|introduce|implement|support|new|allow|enable|expose)\b"
    r"|\b(?:add|added|adds) support\b|\bnew (?:option|setting|widget|command|backend)\b", re.I)
FIX_CUE_RE = re.compile(
    r"\b(?:fix(?:es|ed)?|regression|crash(?:es|ing)?|leak|broken|no longer|stop(?:s|ped)? (?:\w+ )?(?:crash|leak|spam)\w*)\b", re.I)


def categorize(labels, subject):
    for key in CATEGORIES:
        if key in labels:
            return key
    subject = subject or ""
    for rx, key in SUBJECT_HINTS:
        if rx.search(subject):
            return key
    body = AREA_PREFIX_RE.sub("", TYPE_PREFIX_RE.sub("", subject, count=1), count=1)
    if INTERNAL_PREFIX_RE.search(subject):
        return "other"
    if FEATURE_CUE_RE.search(body):
        return "feature"
    if FIX_CUE_RE.search(body):
        return "fix"
    return "other"


def build_entries(repo, rng, use_api=True):
    """One entry per PR (or per direct commit). Ported commits resolve to origin."""
    commits = git_commits(rng)
    lookup_shas = []
    origin_of = {}
    for sha, _an, _ae, _subj, body in commits:
        m = CHERRY_RE.search(body or "")
        origin_of[sha] = m.group(1) if m else sha
        lookup_shas.append(origin_of[sha])
    pr_data = fetch_pr_data(repo, lookup_shas) if use_api else {}

    entries, seen_prs = [], set()
    for sha, an, ae, subject, _body in commits:
        info = pr_data.get(origin_of[sha], {})
        login = info.get("login")
        if login and BOT_RE.search(login):
            continue
        if not login and BOT_RE.search(an):
            continue
        number = info.get("number")
        if number:
            if number in seen_prs:
                continue
            seen_prs.add(number)
        else:
            m = PR_REF_RE.search(subject)
            if m:
                number = int(m.group(1))
                if number in seen_prs:
                    continue
                seen_prs.add(number)
        entries.append({
            "sha": sha, "subject": subject,
            "title": info.get("title") or re.sub(PR_REF_RE, "", subject).strip(),
            "number": number,
            "pr_url": info.get("url") or (number and f"https://github.com/{repo}/pull/{number}"),
            "login": login, "author_name": an, "author_email": ae,
            "author_url": info.get("author_url") or (login and f"https://github.com/{login}"),
            "category": categorize(info.get("labels", []), info.get("title") or subject),
        })

    by_email, by_name = {}, {}
    for e in entries:
        if e["login"]:
            by_email.setdefault(e["author_email"].lower(), e)
            by_name.setdefault(e["author_name"].lower(), e)
            by_name.setdefault(e["login"].lower(), e)
    for e in entries:
        if not e["login"]:
            match = (by_email.get(e["author_email"].lower())
                     or by_name.get(e["author_name"].lower()))
            if match:
                e["login"] = match["login"]
                e["author_url"] = match["author_url"]
    return entries


def author_md(e):
    if e["login"]:
        return f"@{e['login']}"
    return e["author_name"]


def format_sections(entries, escape=lambda t: t):
    out = []
    for key, heading in CATEGORIES.items():
        group = [e for e in entries if e["category"] == key]
        if not group:
            continue
        out.append(f"### {heading}")
        for e in group:
            ref = f" in #{e['number']}" if e["number"] else f" ({e['sha'][:7]})"
            out.append(f"- {escape(e['title'])} by {author_md(e)}{ref}")
        out.append("")
    return out


def format_github(repo, entries, rng, bare=False):
    prev = rng.split("..")[0]
    tag = rng.split("..")[1] if ".." in rng else "HEAD"
    out = [] if bare else ["## What's Changed", ""]
    out += format_sections(entries)
    if not bare:
        out.append(f"**Full Changelog**: https://github.com/{repo}/compare/{prev}...{tag}")
    return "\n".join(out)


def mdx_safe(text):
    # titles land in MDX: escape JSX/expression/table chars
    return (text.replace("{", "&#123;").replace("<", "&lt;")
            .replace("|", "\\|"))


# Same sections as the GitHub body the release feed parses, so docs and shell never disagree.
def format_changelog(repo, entries, rng):
    tag = rng.split("..")[1] if ".." in rng else "HEAD"
    date = run(["git", "log", "-1", "--format=%cs", tag]).strip()
    out = [f"## {tag}", "", f"**Released**: {date}", ""]
    out += format_sections(entries, mdx_safe)
    out += [f"**GitHub Release**: https://github.com/{repo}/releases/tag/{tag}", "", "---"]
    return "\n".join(out)


TYPE_PREFIX_RE = re.compile(
    r"^(?:feat(?:ure)?|fix(?:es)?|hotfix|bugfix|docs?|refactor|chore|perf"
    r"|style|test|i18n|build|ci)\b!?\s*(?:\([^)]*\))?\s*[:/\-]\s*", re.I)
AREA_PREFIX_RE = re.compile(r"^(?:\([^)]*\)|[\w./-]{1,24}):\s+")


def clean_title(title):
    """De-robotize a commit/PR title for prose: drop type/area prefixes."""
    t = title.strip()
    for _ in range(3):
        stripped = TYPE_PREFIX_RE.sub("", t)
        if stripped == t:
            stripped = AREA_PREFIX_RE.sub("", t)
        if stripped == t or not stripped:
            break
        t = stripped.strip()
    return (t[:1].upper() + t[1:]) if t else title


def format_blog(repo, entries, rng, exclude=frozenset()):
    def is_excluded(e):
        return ((e["login"] or "").lower() in exclude
                or e["author_name"].lower() in exclude)

    def table(group):
        rows = {}
        for e in group:
            name = e["login"] or e["author_name"]
            key = name.lower()
            rows.setdefault(key, {"e": e, "name": name, "items": []})
            pr = (f"[PR #{e['number']}]({e['pr_url']})" if e["number"]
                  else f"`{e['sha'][:7]}`")
            rows[key]["items"].append(f"{mdx_safe(clean_title(e['title']))} ({pr})")
        lines = ["| Contributor | Contribution |", "|---|---|"]
        for key in sorted(rows):
            r = rows[key]
            handle = (f"**[{r['name']}]({r['e']['author_url']})**" if r["e"]["author_url"]
                      else f"**{r['name']}**")
            items = r["items"]
            cell = (items[0] if len(items) == 1
                    else "<br/>".join(f"• {it}" for it in items))
            lines.append(f"| {handle} | {cell} |")
        return "\n".join(lines)

    def fix_item(e):
        title = mdx_safe(clean_title(e["title"])).rstrip(".")
        ref = f"[PR #{e['number']}]({e['pr_url']})" if e["number"] else f"`{e['sha'][:7]}`"
        if not is_excluded(e) and e["author_url"]:
            name = e["login"] or e["author_name"]
            return f"- {title} (contributed by **[{name}]({e['author_url']})** {ref})."
        return f"- {title} ({ref})."

    # fixes list includes excluded authors; credit shown for the rest
    fixes, seen_titles = [], set()
    for e in sorted((e for e in entries if e["category"] == "fix"),
                    key=lambda e: clean_title(e["title"]).lower()):
        t = clean_title(e["title"]).lower()
        if t in seen_titles:
            continue
        seen_titles.add(t)
        fixes.append(fix_item(e))

    # tables cover non-fix work; fix authors are credited inline above
    community = [e for e in entries if not is_excluded(e)]
    feats = [e for e in community if e["category"] in ("feature", "breaking")]
    rest = [e for e in community
            if e["category"] not in ("feature", "breaking", "fix")]
    contributors = {(e["login"] or e["author_name"]).lower() for e in community}

    out = []
    if fixes:
        out += ["<!-- paste under \"## Bug Fixes and Improvements\" -->",
                "<details>",
                f"<summary>View Details ({len(fixes)} fixes in {rng})</summary>", ""]
        out += fixes
        out += ["", "</details>", ""]
    out += ["## Community Contributors", "",
            f"<!-- {len(contributors)} community contributors in {rng} -->", ""]
    if feats:
        out += ["### Feature Contributors", "", table(feats), ""]
    if rest:
        out += ["### General Contributions", "", table(rest), ""]
    return "\n".join(out)


def format_checklist(entries):
    out = []
    for e in entries:
        ref = f"#{e['number']}" if e["number"] else e["sha"][:7]
        out.append(f"- [ ] {ref} {e['title']} — {author_md(e)} [{e['category']}]")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("range", help="git range, e.g. v1.4.6..v1.5.0")
    ap.add_argument("--format", choices=["github", "changelog", "blog", "checklist"], default="github")
    ap.add_argument("--repo", default=None, help="owner/name (default: from origin)")
    ap.add_argument("--exclude", action="append", default=None, metavar="LOGIN",
                    help="drop this author (repeatable). Blog format defaults "
                         f"to maintainers ({', '.join(MAINTAINERS)}); pass "
                         "--exclude to override, --exclude '' for nobody")
    ap.add_argument("--bare", action="store_true",
                    help="github format: omit heading and Full Changelog footer")
    ap.add_argument("--no-api", action="store_true",
                    help="skip GitHub API, use git data only (degraded attribution)")
    ap.add_argument("-o", "--output", default=None, metavar="PATH",
                    help="write the output to PATH instead of stdout (parent dirs "
                         "are created)")
    ap.add_argument("--version", default=None, metavar="X.Y.Z",
                    help="release version being cut; if set and -o/--output isn't, "
                         "writes to ~/Documents/dms-vX.Y.Z-changelog.md instead of "
                         "stdout")
    args = ap.parse_args()

    repo = args.repo
    if not repo:
        url = run(["git", "remote", "get-url", "origin"]).strip()
        m = re.search(r"github\.com[:/]([^/]+/[^/.]+)", url)
        repo = m.group(1) if m else "duxlabs-dev/dux-shell"

    entries = build_entries(repo, args.range, use_api=not args.no_api)
    if not entries:
        print("no commits in range", file=sys.stderr)
        return 1
    excludes = args.exclude
    if excludes is None:
        excludes = MAINTAINERS if args.format == "blog" else []
    drop = {x.lower() for x in excludes if x}
    if args.format == "blog":
        # blog excludes from tables only; fixes list keeps everyone
        text = format_blog(repo, entries, args.range, exclude=frozenset(drop))
    else:
        if drop:
            entries = [e for e in entries
                       if (e["login"] or "").lower() not in drop
                       and e["author_name"].lower() not in drop]
        if args.format == "github":
            text = format_github(repo, entries, args.range, bare=args.bare)
        elif args.format == "changelog":
            text = format_changelog(repo, entries, args.range)
        else:
            text = format_checklist(entries)

    out_target = args.output or (f"~/Documents/dms-v{args.version}-changelog.md" if args.version else None)
    if out_target:
        out_path = Path(out_target).expanduser()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text + "\n")
        print(f"written to {out_path}", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
