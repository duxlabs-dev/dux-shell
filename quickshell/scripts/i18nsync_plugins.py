#!/usr/bin/env python3

import sys
import json
import subprocess
import time
from pathlib import Path

from i18nsync import (
    REPO_ROOT, EN_JSON, COMMON_EN_JSON, LANGUAGES,
    OFFICIAL_PLUGINS_REPO, OFFICIAL_PLUGINS_DIR,
    error, warn, info, success, get_env_or_error,
    poeditor_request, poeditor_upload, upload_source_strings, export_language, list_terms,
    normalize_json, json_changed, write_if_changed, git, clone_or_update, entry_keys, load_common_entries,
)

sys.path.insert(0, str(REPO_ROOT / "translations"))
from extract_translations import extract_plugin_strings, create_plugin_poeditor_json, split_plugin_context

# I18n.trFor terms of every supported plugin live in the DankPlugins
# POEditor project, keyed by context "<pluginId>:<term>" so two plugins can
# translate the same English term differently. Supported: the official
# monorepo plus every registry plugin flagged "i18n": true. Exports are
# written back into each checkout's translations/ dir with the prefix
# stripped, which is the shape PluginService loads at runtime.
PLUGIN_REGISTRY_REPO = "https://github.com/duxlabs-dev/dux-plugin-registry.git"
EXTERNAL_PLUGINS_DIR = REPO_ROOT / "dms-plugins-external"
REGISTRY_DIR = EXTERNAL_PLUGINS_DIR / ".registry"
SYNC_STATE = REPO_ROOT / ".git" / "i18n_plugins_sync_state.json"

PLUGIN_PR_BRANCH = "i18n/poeditor-sync"
PLUGIN_PR_TITLE = "i18n: sync translations from POEditor"

DELETE_BATCH = 100

def i18n_registry_plugins():
    plugins = {}
    for entry_file in sorted((REGISTRY_DIR / 'plugins').glob('*.json')):
        with open(entry_file) as f:
            entry = json.load(f)
        if entry.get('i18n') is not True:
            continue
        if not entry.get('id') or not entry.get('repo'):
            error(f"Registry entry {entry_file.name} has i18n set but no id or repo")
        plugins[entry['id']] = entry
    return plugins

def update_plugin_checkouts():
    clone_or_update(OFFICIAL_PLUGINS_REPO, OFFICIAL_PLUGINS_DIR)
    clone_or_update(PLUGIN_REGISTRY_REPO, REGISTRY_DIR)
    plugins = i18n_registry_plugins()
    for plugin_id, entry in plugins.items():
        clone_or_update(entry['repo'], EXTERNAL_PLUGINS_DIR / plugin_id)
    for child in EXTERNAL_PLUGINS_DIR.iterdir():
        if child.is_dir() and not child.name.startswith('.') and child.name not in plugins:
            warn(f"dms-plugins-external/{child.name} is not flagged i18n in the registry but its terms still get uploaded; remove it if it was unapproved")
    success(f"Plugin checkouts current: official + {len(plugins)} registry plugins")

def checkout_candidates():
    if OFFICIAL_PLUGINS_DIR.is_dir():
        yield from sorted(OFFICIAL_PLUGINS_DIR.iterdir())
    if not EXTERNAL_PLUGINS_DIR.is_dir():
        return
    paths = {plugin_id: entry.get('path') or '' for plugin_id, entry in i18n_registry_plugins().items()}
    for child in sorted(EXTERNAL_PLUGINS_DIR.iterdir()):
        if child.name.startswith('.'):
            continue
        yield child / paths.get(child.name, '')

def plugin_checkouts():
    return [
        path for path in checkout_candidates()
        if not path.name.startswith('.') and (path / 'plugin.json').is_file()
    ]

def manifest_id(checkout):
    with open(checkout / 'plugin.json') as f:
        return json.load(f).get('id')

def find_checkout(plugin_id):
    for checkout in plugin_checkouts():
        if manifest_id(checkout) == plugin_id or checkout.name == plugin_id:
            return checkout
    error(f"No plugin checkout for '{plugin_id}' under dms-plugins/ or dms-plugins-external/")

def extract_plugin_entries(checkouts):
    entries = []
    owners = {}
    shell_terms = {}
    for checkout in checkouts:
        scoped, plain = extract_plugin_strings(checkout)
        expected = manifest_id(checkout)
        for plugin_id in sorted({plugin_id for plugin_id, _ in scoped}):
            if plugin_id != expected:
                warn(f"{checkout.name}: I18n.trFor uses id '{plugin_id}' but plugin.json says '{expected}'; runtime never resolves the mismatch")
            if plugin_id in owners and owners[plugin_id] != checkout:
                error(f"Plugin id '{plugin_id}' is used by both {owners[plugin_id].name} and {checkout.name}")
            owners[plugin_id] = checkout
        entries.extend(create_plugin_poeditor_json(scoped))
        shell_terms[checkout] = plain
    return entries, owners, shell_terms

def warn_unresolved_shell_terms(shell_terms):
    catalog = {e['term'] for e in normalize_json(EN_JSON)} | {e['term'] for e in normalize_json(COMMON_EN_JSON)}
    for checkout, plain in sorted(shell_terms.items(), key=lambda item: item[0].name):
        missing = sorted(term for term in plain if term not in catalog)
        if not missing:
            continue
        warn(f"{checkout.name}: {len(missing)} I18n.tr terms are not in the shell catalog and stay untranslated (use I18n.trFor):")
        for term in missing[:10]:
            occ = plain[term][0]
            print(f"  {term!r} ({occ['file']}:{occ['line']})", file=sys.stderr)
        if len(missing) > 10:
            print(f"  ... and {len(missing) - 10} more", file=sys.stderr)

def gh(args, cwd=None, required=True):
    result = subprocess.run(['gh', *args], cwd=cwd, capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.strip()
    if required:
        error(f"gh {' '.join(args)} failed:\n{result.stderr.strip()}")
    return None

def git_output(args, cwd):
    result = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return result.stdout.strip()

def repo_slug(checkout):
    url = git_output(['remote', 'get-url', 'origin'], checkout) or ""
    if 'github.com' not in url:
        return None
    return url.removesuffix('.git').split('github.com', 1)[1].lstrip(':/')

def default_branch(checkout):
    ref = git_output(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], checkout)
    if not ref:
        return 'main'
    return ref.split('/', 1)[-1]

def pending_translation_files(checkout):
    out = git_output(['status', '--porcelain', '--untracked-files=all', '--', 'translations'], checkout)
    if not out:
        return []
    names = (line[3:].rsplit('/', 1)[-1] for line in out.splitlines())
    return sorted(name for name in names if name.endswith('.json'))

def pending_plugin_prs():
    external = []
    official = []
    for checkout in plugin_checkouts():
        files = pending_translation_files(checkout)
        if not files:
            continue
        if checkout.is_relative_to(EXTERNAL_PLUGINS_DIR):
            external.append((checkout, files))
        else:
            official.append((checkout, files))
    return external, official

def plugin_pr_body(files):
    return (
        "Translations synced from the DankPlugins POEditor project, where this plugin's "
        "I18n.trFor strings are translated by the DMS community.\n\n"
        f"Updated: {', '.join(sorted(files))}\n\n"
        "Strings this repo already shipped were uploaded to POEditor before the export, "
        "so existing translations are preserved rather than overwritten.\n"
    )

def user_fork(slug, login):
    forks = gh(['api', '--paginate', f'repos/{slug}/forks', '-q', f'.[] | select(.owner.login == "{login}") | .full_name'])
    if forks:
        return forks.splitlines()[0]
    info(f"Forking {slug}")
    return gh(['api', '-X', 'POST', f'repos/{slug}/forks', '-q', '.full_name'])

def push_to_fork(checkout, fork):
    # a fresh fork is created asynchronously and can reject pushes briefly
    for _ in range(5):
        pushed = subprocess.run(
            ['git', 'push', '--quiet', '--force', f'git@github.com:{fork}.git', PLUGIN_PR_BRANCH],
            cwd=checkout, capture_output=True, text=True
        )
        if pushed.returncode == 0:
            return None
        time.sleep(5)
    return pushed.stderr.strip()

def open_plugin_pr(checkout, files):
    slug = repo_slug(checkout)
    if not slug:
        warn(f"{checkout.name}: origin is not a github remote, skipping PR")
        return

    login = gh(['api', 'user', '-q', '.login'])
    fork = user_fork(slug, login)

    base = default_branch(checkout)
    git(['checkout', '--quiet', '-B', PLUGIN_PR_BRANCH], checkout)
    git(['add', 'translations'], checkout)

    committed = subprocess.run(
        ['git', 'commit', '--quiet', '-m', PLUGIN_PR_TITLE],
        cwd=checkout, capture_output=True, text=True
    )
    if committed.returncode != 0:
        git(['checkout', '--quiet', base], checkout)
        warn(f"{checkout.name}: nothing to commit, skipping PR")
        return

    push_error = push_to_fork(checkout, fork)
    git(['checkout', '--quiet', base], checkout)
    if push_error:
        warn(f"{checkout.name}: push to {fork} failed, re-run sync to retry:\n{push_error}")
        return

    existing = gh([
        'pr', 'list', '--repo', slug, '--head', PLUGIN_PR_BRANCH, '--state', 'open',
        '--json', 'url,headRepositoryOwner', '-q', f'.[] | select(.headRepositoryOwner.login == "{login}") | .url'
    ], required=False)
    if existing:
        success(f"{checkout.name}: updated {existing}")
        return

    url = gh([
        'pr', 'create', '--repo', slug, '--base', base, '--head', f'{login}:{PLUGIN_PR_BRANCH}',
        '--title', PLUGIN_PR_TITLE, '--body', plugin_pr_body(files)
    ])
    success(f"{checkout.name}: opened {url}")

def report_pending_prs(open_prs):
    pending_prs, official_pending = pending_plugin_prs()
    for checkout, files in official_pending:
        info(f"{checkout.name}: {len(files)} translation files to commit in dms-plugins")
    if open_prs:
        for checkout, files in pending_prs:
            open_plugin_pr(checkout, files)
        return
    for checkout, files in pending_prs:
        info(f"{checkout.name} has {len(files)} uncommitted translation files")
    if pending_prs:
        info("Re-run without --no-pr (or run 'pr') to push them to your fork and open the PRs upstream.")

def checkout_translations(checkout, filename):
    result = subprocess.run(
        ['git', 'show', f'HEAD:./translations/{filename}'],
        cwd=checkout, capture_output=True, text=True
    )
    if result.returncode != 0:
        return {}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        warn(f"{checkout.name}/translations/{filename} is not valid JSON in git HEAD")
        return {}

def keep_existing_translations(existing, incoming):
    return {
        context: {term: value or existing.get(context, {}).get(term, "") for term, value in bucket.items()}
        for context, bucket in incoming.items()
    }

def missing_from_poeditor(existing, incoming):
    gaps = {}
    for context, bucket in incoming.items():
        for term, value in bucket.items():
            if value:
                continue
            local = existing.get(context, {}).get(term, "")
            if not local:
                continue
            gaps[(context, term)] = local
    return gaps

def split_plugin_export(data, owners):
    parts = {}
    unknown = set()
    for context, terms in data.items():
        if not isinstance(terms, dict):
            continue
        plugin_id, local_context = split_plugin_context(context)
        checkout = owners.get(plugin_id)
        if not checkout:
            unknown.add(plugin_id or context)
            continue
        for term, value in terms.items():
            parts.setdefault(plugin_id, {}).setdefault(local_context, {})[term] = value
    return parts, unknown

def download_translations(api_token, project_id, owners):
    info("Downloading translations from POEditor...")
    changed = {}
    seed = {}
    unknown = set()

    for po_lang, filename in LANGUAGES.items():
        info(f"Fetching {po_lang}...")
        data = export_language(api_token, project_id, po_lang)
        if data is None:
            continue

        parts, lang_unknown = split_plugin_export(data, owners)
        unknown |= lang_unknown

        for plugin_id, part in sorted(parts.items()):
            checkout = owners[plugin_id]
            target_dir = checkout / "translations"
            target_dir.mkdir(parents=True, exist_ok=True)
            existing = checkout_translations(checkout, filename)
            for (context, term), value in missing_from_poeditor(existing, part).items():
                seed.setdefault(po_lang, {})[(plugin_id, context, term)] = value
            if write_if_changed(target_dir / filename, keep_existing_translations(existing, part)):
                success(f"Updated {checkout.name} {filename}")
                changed.setdefault(checkout.name, []).append(filename)

    if unknown:
        warn(f"POEditor holds terms for plugins with no checkout, left untouched: {', '.join(sorted(unknown))}")
    return changed, seed

def seed_plugin_translations(api_token, project_id, seed):
    seeded = {}
    for po_lang, values in sorted(seed.items()):
        entries = [
            {'term': term, 'context': f"{plugin_id}:{context}", 'definition': value}
            for (plugin_id, context, term), value in sorted(values.items())
        ]
        info(f"Seeding {len(entries)} plugin-authored translations into POEditor ({po_lang})...")
        result = poeditor_upload({
            'api_token': api_token,
            'id': project_id,
            'updating': 'translations',
            'language': po_lang,
            'overwrite': '0',
            'fuzzy_trigger': '0'
        }, entries, LANGUAGES[po_lang], required=False)
        if not result:
            continue
        translations = result.get('translations', {})
        applied = translations.get('added', 0) + translations.get('updated', 0)
        if not applied:
            warn(f"POEditor accepted the {po_lang} seed but applied nothing: {translations}")
            continue
        seeded[po_lang] = applied
    return seeded

def report_seed(api_token, project_id, seed, apply):
    pending = sum(len(values) for values in seed.values())
    if not pending:
        return
    if not apply:
        info(f"{pending} plugin-authored translations are missing from POEditor across {len(seed)} languages.")
        info("Re-run with --seed to adopt them (one throttled upload per language).")
        return
    seeded = seed_plugin_translations(api_token, project_id, seed)
    if seeded:
        info("Plugin-authored translations adopted into POEditor: " + ", ".join(f"{lang} +{count}" for lang, count in sorted(seeded.items())))

def load_state():
    return normalize_json(SYNC_STATE) or {}

def save_state(entries, owners):
    state = {'entries': entries, 'translations': {}}
    for checkout in set(owners.values()):
        state['translations'][checkout.name] = {
            filename: normalize_json(checkout / 'translations' / filename)
            for filename in LANGUAGES.values()
        }
    SYNC_STATE.parent.mkdir(parents=True, exist_ok=True)
    with open(SYNC_STATE, 'w') as f:
        json.dump(state, f, indent=2)

def term_diff(local_entries, remote_terms):
    local = entry_keys(local_entries)
    remote = entry_keys(remote_terms)
    return sorted(local - remote), sorted(remote - local)

def print_term_diff(added, removed, prune):
    for context, term in added[:15]:
        print(f"  + {context}")
    if len(added) > 15:
        print(f"  ... and {len(added) - 15} more")
    for context, term in removed[:15]:
        print(f"  - {context}" + ("" if prune else " (kept, no --prune)"))
    if len(removed) > 15:
        print(f"  ... and {len(removed) - 15} more")

def cmd_sync(flags):
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    project_id = get_env_or_error('POEDITOR_PLUGINS_PROJECT_ID')
    prune = '--prune' in flags
    open_prs = '--no-pr' not in flags
    seed = '--seed' in flags
    dry_run = '--dry-run' in flags
    if prune:
        warn("--prune deletes every DankPlugins term missing from the supported plugin checkouts, including its translations.")
        warn("Checkouts are refreshed from the registry first; a plugin removed from the registry loses its terms.")

    update_plugin_checkouts()
    entries, owners, shell_terms = extract_plugin_entries(plugin_checkouts())
    warn_unresolved_shell_terms(shell_terms)
    success(f"Extracted {len(entries)} plugin terms from {len(owners)} plugins: {', '.join(sorted(owners))}")

    if dry_run:
        added, removed = term_diff(entries, list_terms(api_token, project_id))
        info(f"Dry run: {len(added)} terms to add, {len(removed)} in POEditor but not local")
        print_term_diff(added, removed, prune)
        return

    state = load_state()
    terms_changed = json.dumps(entries, sort_keys=True) != json.dumps(state.get('entries'), sort_keys=True)
    if terms_changed or prune:
        upload_source_strings(api_token, project_id, entries, prune)
    else:
        info("No changes in plugin source strings")

    changed, pending_seed = download_translations(api_token, project_id, owners)
    save_state(entries, owners)

    for checkout_name, files in sorted(changed.items()):
        info(f"{checkout_name} translations updated: {', '.join(files)}")
    if not changed:
        info("Plugin translations already in sync")

    report_pending_prs(open_prs)
    report_seed(api_token, project_id, pending_seed, seed)

def cmd_check():
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    project_id = get_env_or_error('POEDITOR_PLUGINS_PROJECT_ID')
    entries, owners, _ = extract_plugin_entries(plugin_checkouts())
    state = load_state()
    if json.dumps(entries, sort_keys=True) != json.dumps(state.get('entries'), sort_keys=True):
        error("plugin i18n out of sync - run 'python3 scripts/i18nsync_plugins.py sync' first")
    for checkout in set(owners.values()):
        for filename in LANGUAGES.values():
            if json_changed(checkout / 'translations' / filename, state.get('translations', {}).get(checkout.name, {}).get(filename, {})):
                error(f"{checkout.name}/translations/{filename} differs from the last sync")
    first_lang = next(iter(LANGUAGES))
    data = export_language(api_token, project_id, first_lang)
    if data is not None:
        parts, _ = split_plugin_export(data, owners)
        for plugin_id, part in parts.items():
            checkout = owners[plugin_id]
            existing = checkout_translations(checkout, LANGUAGES[first_lang])
            if json_changed(checkout / 'translations' / LANGUAGES[first_lang], keep_existing_translations(existing, part)):
                error(f"{checkout.name}: POEditor has newer {first_lang} translations")
    success("plugin i18n in sync")

def translation_index(terms):
    return {
        (t.get('context') or t['term'], t['term']): (t.get('translation') or {}).get('content') or ""
        for t in terms
    }

def plugin_keys(plugin_id, checkout):
    scoped, _ = extract_plugin_strings(checkout)
    entries = [e for e in create_plugin_poeditor_json(scoped) if split_plugin_context(e['context'])[0] == plugin_id]
    if not entries:
        error(f"{checkout.name} has no I18n.trFor(\"{plugin_id}\", ...) calls")
    return entries, [(split_plugin_context(e['context'])[1], e['term']) for e in entries]

def cmd_migrate(plugin_ids, flags):
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    main_id = get_env_or_error('POEDITOR_PROJECT_ID')
    project_id = get_env_or_error('POEDITOR_PLUGINS_PROJECT_ID')
    dry_run = '--dry-run' in flags

    update_plugin_checkouts()
    plugins = {}
    entries = []
    for plugin_id in plugin_ids:
        checkout = find_checkout(plugin_id)
        plugin_entries, keys = plugin_keys(plugin_id, checkout)
        plugins[plugin_id] = (checkout, keys)
        entries.extend(plugin_entries)
        info(f"{plugin_id}: {len(plugin_entries)} terms from {checkout.name}")
    info(f"{len(entries)} terms total" + (" (dry run)" if dry_run else ""))

    if not dry_run:
        upload_source_strings(api_token, project_id, entries)

    print(f"{'lang':<8} {'merged':>6} {'main':>6} {'repo':>6}")
    for po_lang, filename in LANGUAGES.items():
        from_main = translation_index(list_terms(api_token, main_id, po_lang))
        merged = {}
        main_hits = 0
        for plugin_id, (checkout, keys) in plugins.items():
            from_repo = checkout_translations(checkout, filename)
            for context, term in keys:
                value = from_main.get((context, term))
                if value:
                    main_hits += 1
                else:
                    value = from_repo.get(context, {}).get(term, "")
                if value:
                    merged[(plugin_id, context, term)] = value
        print(f"{po_lang:<8} {len(merged):>6} {main_hits:>6} {len(merged) - main_hits:>6}")
        if dry_run or not merged:
            continue
        payload = [
            {'term': term, 'context': f"{plugin_id}:{context}", 'definition': value}
            for (plugin_id, context, term), value in sorted(merged.items())
        ]
        result = poeditor_upload({
            'api_token': api_token,
            'id': project_id,
            'updating': 'translations',
            'language': po_lang,
            'overwrite': '0',
            'fuzzy_trigger': '0'
        }, payload, filename, required=False)
        if result:
            translations = result.get('translations', {})
            info(f"  {po_lang}: {translations.get('added', 0)} added, {translations.get('updated', 0)} updated")

    if dry_run:
        info("Dry run: nothing uploaded. Re-run without --dry-run to migrate.")
        return
    success(f"Migrated into DankPlugins: {', '.join(plugin_ids)}. Run 'sync' next, then 'purge-main'.")

def head_en_json():
    result = subprocess.run(
        ['git', 'show', f'HEAD:./{EN_JSON.relative_to(REPO_ROOT)}'],
        capture_output=True, text=True, cwd=REPO_ROOT
    )
    if result.returncode != 0:
        error("Cannot read translations/en.json from git HEAD")
    return json.loads(result.stdout)

def cmd_purge_main(plugin_ids, flags):
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    main_id = get_env_or_error('POEDITOR_PROJECT_ID')
    project_id = get_env_or_error('POEDITOR_PLUGINS_PROJECT_ID')
    dry_run = '--dry-run' in flags
    confirmed = '--yes' in flags

    update_plugin_checkouts()
    owners = {}
    current = {}
    for plugin_id in plugin_ids:
        checkout = find_checkout(plugin_id)
        _, keys = plugin_keys(plugin_id, checkout)
        owners[f"plugin-{plugin_id.lower()}"] = plugin_id
        current[plugin_id] = set(keys)

    shared = entry_keys(load_common_entries())
    candidates = {}
    for entry in head_en_json():
        tags = entry.get('tags') or []
        if not tags or not set(tags) <= set(owners):
            continue
        key = (entry['context'] or entry['term'], entry['term'])
        if key in shared:
            continue
        candidates[key] = [owners[tag] for tag in tags]
    if not candidates:
        error(f"No terms in the committed en.json are used only by {', '.join(plugin_ids)}; nothing to purge")
    info(f"{len(candidates)} terms in the committed en.json are used only by these plugins")

    main_keys = entry_keys(list_terms(api_token, main_id))
    candidates = {key: ids for key, ids in candidates.items() if key in main_keys}
    info(f"{len(candidates)} of them exist in the main project")

    users = {key: [pid for pid in ids if key in current[pid]] for key, ids in candidates.items()}
    dead = sorted(key for key, ids in users.items() if not ids)
    live = {key: ids for key, ids in users.items() if ids}
    info(f"{len(live)} still used, {len(dead)} no longer in any plugin (deleted outright, translations not carried over)")
    for context, term in dead[:15]:
        print(f"  dead: {context}")
    if len(dead) > 15:
        print(f"  ... and {len(dead) - 15} more")

    plugin_keys_remote = entry_keys(list_terms(api_token, project_id))
    missing = [
        (key, pid) for key, ids in live.items() for pid in ids
        if (f"{pid}:{key[0]}", key[1]) not in plugin_keys_remote
    ]
    if missing:
        for (context, term), pid in missing[:15]:
            print(f"  missing in DankPlugins: {pid}:{context}")
        error(f"{len(missing)} plugin terms are not in DankPlugins yet; run 'migrate' first")

    print(f"{'lang':<8} {'main':>6} {'plugins':>8} {'lost':>6}")
    lost_any = False
    for po_lang in LANGUAGES:
        from_main = translation_index(list_terms(api_token, main_id, po_lang))
        from_plugins = translation_index(list_terms(api_token, project_id, po_lang))
        translated = [key for key in live if from_main.get(key)]
        lost = [
            key for key in translated
            if any(not from_plugins.get((f"{pid}:{key[0]}", key[1])) for pid in live[key])
        ]
        lost_any = lost_any or bool(lost)
        print(f"{po_lang:<8} {len(translated):>6} {len(translated) - len(lost):>8} {len(lost):>6}")
    if lost_any:
        error("Some main translations are missing in DankPlugins; run 'migrate' again before purging")

    doomed = sorted(set(live) | set(dead))
    if dry_run:
        info(f"Dry run: nothing deleted. {len(doomed)} terms would go.")
        return
    if not confirmed:
        error(f"Re-run with --yes to delete these {len(doomed)} terms from the main project")

    deleted = 0
    for start in range(0, len(doomed), DELETE_BATCH):
        batch = [{'term': term, 'context': context} for context, term in doomed[start:start + DELETE_BATCH]]
        resp = poeditor_request('terms/delete', {'api_token': api_token, 'id': main_id, 'data': json.dumps(batch)})
        if resp.get('response', {}).get('status') != 'success':
            error(f"terms/delete failed after {deleted} deletions: {resp}")
        deleted += resp.get('result', {}).get('terms', {}).get('deleted', 0)
    success(f"Deleted {deleted} terms from the main project. Run 'i18nsync.py sync' to refresh en.json and poexports.")

def main():
    usage = "Usage: i18nsync_plugins.py sync [--prune] [--no-pr] [--seed] [--dry-run] | check | pr | migrate <pluginId>... [--dry-run] | purge-main <pluginId>... [--dry-run] [--yes]"
    if len(sys.argv) < 2:
        error(usage)
    command = sys.argv[1]
    args = sys.argv[2:]
    flags = [a for a in args if a.startswith('--')]
    positional = [pid for a in args if not a.startswith('--') for pid in a.split()]

    if command == 'sync':
        cmd_sync(flags)
    elif command == 'check':
        cmd_check()
    elif command == 'pr':
        report_pending_prs(True)
    elif command == 'migrate':
        if not positional:
            error(usage)
        cmd_migrate(positional, flags)
    elif command == 'purge-main':
        if not positional:
            error(usage)
        cmd_purge_main(positional, flags)
    else:
        error(f"Unknown command: {command}")

if __name__ == '__main__':
    main()
