#!/usr/bin/env python3

import sys
import json
import os
import subprocess
import time
from pathlib import Path
from urllib import request, parse

REPO_ROOT = Path(__file__).parent.parent
EN_JSON = REPO_ROOT / "translations" / "en.json"
TEMPLATE_JSON = REPO_ROOT / "translations" / "template.json"
POEXPORTS_DIR = REPO_ROOT / "translations" / "poexports"
SYNC_STATE = REPO_ROOT / ".git" / "i18n_sync_state.json"
TERM_RENAMES_JSON = REPO_ROOT / "translations" / "term_renames.json"

# dux-qml-common terms live in the same DMS POEditor project (tagged
# dank-qml-common); their translations ship inside the submodule so every
# consumer gets them with the pointer. dankcalendar merges from this project.
COMMON_ROOT = REPO_ROOT.parent / "dux-qml-common"
COMMON_EN_JSON = COMMON_ROOT / "translations" / "en.json"
COMMON_POEXPORTS_DIR = COMMON_ROOT / "DCommon" / "translations" / "poexports"

# The official plugin monorepo is scanned by extraction: its plugins use
# I18n.tr, so their terms belong to the shell catalog. I18n.trFor terms
# (external registry plugins) are owned by the DankPlugins project, see
# i18nsync_plugins.py.
OFFICIAL_PLUGINS_REPO = "https://github.com/duxlabs-dev/dux-plugins.git"
OFFICIAL_PLUGINS_DIR = REPO_ROOT / "dms-plugins"

RATE_LIMIT_CODE = '4048'
# https://poeditor.com/docs/api_rates: 1 upload per 20s free, 10s paid.
UPLOAD_MIN_INTERVAL = float(os.environ.get('POEDITOR_UPLOAD_INTERVAL', 20))
UPLOAD_RETRIES = 4
_last_upload = 0.0

LANGUAGES = {
    "ja": "ja.json",
    "zh-Hans": "zh_CN.json",
    "zh-Hant": "zh_TW.json",
    "pt-br": "pt.json",
    "tr": "tr.json",
    "it": "it.json",
    "pl": "pl.json",
    "es": "es.json",
    "he": "he.json",
    "hu": "hu.json",
    "fa": "fa.json",
    "fr": "fr.json",
    "nl": "nl.json",
    "ru": "ru.json",
    "de": "de.json",
    "sv": "sv.json",
    "vi": "vi.json",
    "eo": "eo.json",
    "ko": "ko.json",
    "ar": "ar.json",
    "uk": "uk.json",
    "bg": "bg.json"
}

def error(msg):
    print(f"\033[91mError: {msg}\033[0m", file=sys.stderr)
    sys.exit(1)

def warn(msg):
    print(f"\033[93mWarning: {msg}\033[0m", file=sys.stderr)

def info(msg):
    print(f"\033[94m{msg}\033[0m")

def success(msg):
    print(f"\033[92m{msg}\033[0m")

def get_env_or_error(var):
    value = os.environ.get(var)
    if not value:
        error(f"{var} environment variable not set")
    return value

def poeditor_request(endpoint, data):
    url = f"https://api.poeditor.com/v2/{endpoint}"
    data_bytes = parse.urlencode(data).encode()
    req = request.Request(url, data=data_bytes, method="POST")

    try:
        with request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        error(f"POEditor API request failed: {e}")

def export_language(api_token, project_id, po_lang):
    export_resp = poeditor_request('projects/export', {
        'api_token': api_token,
        'id': project_id,
        'language': po_lang,
        'type': 'key_value_json'
    })

    if export_resp.get('response', {}).get('status') != 'success':
        warn(f"Export request failed for {po_lang}")
        return None

    url = export_resp.get('result', {}).get('url')
    if not url:
        warn(f"No export URL for {po_lang}")
        return None

    try:
        with request.urlopen(url) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        warn(f"Failed to download {po_lang}: {e}")
        return None

def list_terms(api_token, project_id, language=None):
    data = {'api_token': api_token, 'id': project_id}
    if language:
        data['language'] = language
    resp = poeditor_request('terms/list', data)
    if resp.get('response', {}).get('status') != 'success':
        error(f"POEditor terms list failed: {resp}")
    return resp.get('result', {}).get('terms', [])

def extract_strings():
    info("Extracting strings from QML files...")
    extract_script = REPO_ROOT / "translations" / "extract_translations.py"

    if not extract_script.exists():
        error(f"Extract script not found: {extract_script}")

    result = subprocess.run([sys.executable, str(extract_script)], cwd=REPO_ROOT)
    if result.returncode != 0:
        error("String extraction failed")

    if not EN_JSON.exists():
        error(f"Extraction did not produce {EN_JSON}")

def normalize_json(file_path):
    if not file_path.exists():
        return {}
    with open(file_path) as f:
        return json.load(f)

def json_changed(file_path, new_data):
    old_data = normalize_json(file_path)
    return json.dumps(old_data, sort_keys=True) != json.dumps(new_data, sort_keys=True)

def load_common_entries():
    if not COMMON_EN_JSON.exists():
        error("dux-qml-common submodule not initialized (git submodule update --init)")
    with open(COMMON_EN_JSON) as f:
        entries = json.load(f)
    return [{**e, "tags": sorted(set(e.get("tags", [])) | {"dank-qml-common"})} for e in entries]

# dms-greeter terms live in this POEditor project but are owned by the
# dank-greeter repo. They must ride along in every upload so prune
# (sync_terms) does not delete them and tag-less uploads do not strip
# their tag.
GREETER_TAG = "dms-greeter"

def load_greeter_entries(api_token, project_id):
    return [
        {'term': t['term'], 'context': t.get('context', ''), 'tags': sorted(set(t.get('tags', [])))}
        for t in list_terms(api_token, project_id)
        if GREETER_TAG in t.get('tags', [])
    ]

def entry_keys(entries):
    return {(e.get('context') or e['term'], e['term']) for e in entries}

def git(args, cwd):
    result = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        error(f"git {' '.join(args)} in {cwd} failed:\n{result.stderr.strip()}")

def clone_or_update(url, path):
    rel = path.relative_to(REPO_ROOT)
    if not (path / '.git').is_dir():
        info(f"Cloning {url} -> {rel}")
        path.parent.mkdir(parents=True, exist_ok=True)
        git(['clone', '--quiet', url, str(path)], REPO_ROOT)
        return
    info(f"Updating {rel}")
    git(['pull', '--quiet', '--ff-only'], path)

def combine_entries(app_entries, common_entries):
    common_by_key = {(e.get('context') or e['term'], e['term']): e for e in common_entries}
    combined = []
    for entry in app_entries:
        key = (entry.get('context') or entry['term'], entry['term'])
        overlap = common_by_key.pop(key, None)
        if overlap:
            entry = {**entry, "tags": sorted(set(entry.get("tags", [])) | set(overlap.get("tags", [])))}
        combined.append(entry)
    return combined + list(common_by_key.values())

def split_export(data, common_keys, greeter_keys):
    app_part = {}
    common_part = {}
    for context, terms in data.items():
        if not isinstance(terms, dict):
            continue
        for term, value in terms.items():
            key = (context, term)
            if key in common_keys:
                common_part.setdefault(context, {})[term] = value
                continue
            if key in greeter_keys:
                continue
            app_part.setdefault(context, {})[term] = value
    return app_part, common_part

def _throttle_upload():
    global _last_upload
    gap = UPLOAD_MIN_INTERVAL - (time.monotonic() - _last_upload)
    if gap <= 0:
        return
    info(f"Waiting {gap:.0f}s for the POEditor upload rate limit...")
    time.sleep(gap)

def poeditor_upload(fields, payload, filename, required=True):
    global _last_upload
    boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW'
    head = ''.join(
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
        f'{value}\r\n'
        for name, value in fields.items()
    ) + (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f'Content-Type: application/json\r\n\r\n'
    )
    body = head.encode() + json.dumps(payload, ensure_ascii=False).encode() + f'\r\n--{boundary}--\r\n'.encode()

    for attempt in range(UPLOAD_RETRIES):
        _throttle_upload()
        req = request.Request(
            'https://api.poeditor.com/v2/projects/upload',
            data=body,
            headers={'Content-Type': f'multipart/form-data; boundary={boundary}'}
        )

        try:
            with request.urlopen(req) as response:
                result = json.loads(response.read().decode())
        except Exception as e:
            _last_upload = time.monotonic()
            result = f"network error: {e}"
            if attempt + 1 < UPLOAD_RETRIES:
                warn(f"Upload failed ({e}), retrying ({attempt + 2}/{UPLOAD_RETRIES})")
            continue

        _last_upload = time.monotonic()
        if result.get('response', {}).get('status') == 'success':
            return result.get('result', {})

        if result.get('response', {}).get('code') != RATE_LIMIT_CODE:
            break

        if attempt + 1 < UPLOAD_RETRIES:
            _last_upload += UPLOAD_MIN_INTERVAL * (attempt + 1)
            warn(f"POEditor rate limited the upload, retrying ({attempt + 2}/{UPLOAD_RETRIES})")

    if required:
        error(f"POEditor upload failed: {result}")
    warn(f"POEditor upload failed: {result}")
    return None

def upload_source_strings(api_token, project_id, entries, prune=False):
    if not entries:
        warn("No terms to upload")
        return False

    info("Uploading source strings to POEditor..." + (" (pruning terms not present locally)" if prune else ""))

    fields = {'api_token': api_token, 'id': project_id, 'updating': 'terms'}
    if prune:
        fields['sync_terms'] = '1'

    terms = poeditor_upload(fields, entries, 'en.json').get('terms', {})
    added = terms.get('added', 0)
    updated = terms.get('updated', 0)
    deleted = terms.get('deleted', 0)

    if not (added or updated or deleted):
        info("No changes uploaded to POEditor")
        return False

    success(f"POEditor updated: {added} added, {updated} updated, {deleted} deleted")
    return True

def load_term_renames():
    if not TERM_RENAMES_JSON.exists():
        return {}
    with open(TERM_RENAMES_JSON) as f:
        data = json.load(f)
    return {old: new for old, new in data.items() if isinstance(new, str) and old != new}


def export_language(api_token, project_id, po_lang):
    export_resp = poeditor_request('projects/export', {
        'api_token': api_token,
        'id': project_id,
        'language': po_lang,
        'type': 'key_value_json'
    })
    url = export_resp.get('result', {}).get('url')
    if export_resp.get('response', {}).get('status') != 'success' or not url:
        warn(f"Export request failed for {po_lang}")
        return None
    try:
        with request.urlopen(url) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        warn(f"Failed to download {po_lang}: {e}")
        return None


def flat_translations(data, out=None):
    out = {} if out is None else out
    for key, value in data.items():
        if isinstance(value, dict):
            flat_translations(value, out)
            continue
        if isinstance(value, str) and value:
            out.setdefault(key, value)
    return out


def collect_rename_translations(api_token, project_id, renames):
    if not renames:
        return {}
    info(f"Collecting translations for {len(renames)} renamed terms...")
    carry = {}
    for po_lang in LANGUAGES:
        data = export_language(api_token, project_id, po_lang)
        if data is None:
            continue
        existing = flat_translations(data)
        entries = [
            {'term': new, 'translation': existing[old]}
            for old, new in renames.items()
            if old in existing and new not in existing
        ]
        if entries:
            carry[po_lang] = entries
    return carry


def apply_rename_translations(api_token, project_id, carry):
    for po_lang, entries in carry.items():
        info(f"Carrying {len(entries)} translations to renamed terms for {po_lang}...")
        poeditor_upload({
            'api_token': api_token,
            'id': project_id,
            'updating': 'terms_translations',
            'language': po_lang,
            'overwrite': '0',
        }, entries, 'en.json')
    if carry:
        success(f"Carried translations over for {len(carry)} languages")


def write_if_changed(repo_file, new_data):
    if not json_changed(repo_file, new_data):
        return False
    with open(repo_file, 'w') as f:
        json.dump(new_data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write('\n')
    return True

def download_translations(api_token, project_id, common_keys, greeter_keys):
    info("Downloading translations from POEditor...")

    POEXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    COMMON_POEXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    any_changed = False
    common_changed = []

    for po_lang, filename in LANGUAGES.items():
        repo_file = POEXPORTS_DIR / filename
        common_file = COMMON_POEXPORTS_DIR / filename

        info(f"Fetching {po_lang}...")
        new_data = export_language(api_token, project_id, po_lang)
        if new_data is None:
            continue

        app_part, common_part = split_export(new_data, common_keys, greeter_keys)

        if write_if_changed(repo_file, app_part):
            success(f"Updated {filename}")
            any_changed = True
        else:
            info(f"No changes for {filename}")

        if write_if_changed(common_file, common_part):
            success(f"Updated dux-qml-common {filename}")
            common_changed.append(filename)

    return any_changed, common_changed

def check_sync_status():
    api_token = get_env_or_error('POEDITOR_API_TOKEN')
    project_id = get_env_or_error('POEDITOR_PROJECT_ID')

    extract_strings()

    current_en = normalize_json(EN_JSON)
    common_entries = load_common_entries()
    common_keys = entry_keys(common_entries)
    greeter_keys = entry_keys(load_greeter_entries(api_token, project_id))

    if not SYNC_STATE.exists():
        return True

    with open(SYNC_STATE) as f:
        state = json.load(f)

    last_en = state.get('en_json', {})
    last_common_en = state.get('common_en_json', {})
    last_translations = state.get('translations', {})
    last_common_translations = state.get('common_translations', {})

    if json.dumps(current_en, sort_keys=True) != json.dumps(last_en, sort_keys=True):
        return True

    if json.dumps(common_entries, sort_keys=True) != json.dumps(last_common_en, sort_keys=True):
        return True

    for po_lang, filename in LANGUAGES.items():
        if json_changed(POEXPORTS_DIR / filename, last_translations.get(filename, {})):
            return True
        if json_changed(COMMON_POEXPORTS_DIR / filename, last_common_translations.get(filename, {})):
            return True

    first_lang, first_file = next(iter(LANGUAGES.items()))
    remote_data = export_language(api_token, project_id, first_lang)
    if remote_data is None:
        return False

    app_part, common_part = split_export(remote_data, common_keys, greeter_keys)
    if json_changed(POEXPORTS_DIR / first_file, app_part):
        return True
    if json_changed(COMMON_POEXPORTS_DIR / first_file, common_part):
        return True

    return False

def save_sync_state():
    state = {
        'en_json': normalize_json(EN_JSON),
        'common_en_json': load_common_entries() if COMMON_EN_JSON.exists() else {},
        'translations': {},
        'common_translations': {}
    }

    for filename in LANGUAGES.values():
        state['translations'][filename] = normalize_json(POEXPORTS_DIR / filename)
        state['common_translations'][filename] = normalize_json(COMMON_POEXPORTS_DIR / filename)

    SYNC_STATE.parent.mkdir(parents=True, exist_ok=True)
    with open(SYNC_STATE, 'w') as f:
        json.dump(state, f, indent=2)

def staged_en():
    result = subprocess.run(
        ['git', 'show', f':./{EN_JSON.relative_to(REPO_ROOT)}'],
        capture_output=True, text=True, cwd=REPO_ROOT
    )
    if result.returncode != 0:
        return {}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

def main():
    if len(sys.argv) < 2:
        error("Usage: i18nsync.py [check|sync [--prune]|test|local]")

    command = sys.argv[1]

    if command == "test":
        info("Running in test mode (no POEditor upload/download)")
        extract_strings()

        current_en = normalize_json(EN_JSON)
        current_template = normalize_json(TEMPLATE_JSON)

        success(f"✓ Extracted {len(current_en)} terms")

        terms_with_context = sum(1 for entry in current_en if entry.get('context') and entry['context'] != entry['term'])
        if terms_with_context > 0:
            success(f"✓ Found {terms_with_context} terms with custom contexts")

        info("\nFiles generated:")
        info(f"  - {EN_JSON}")
        info(f"  - {TEMPLATE_JSON}")

        sys.exit(0)
    elif command == "check":
        try:
            if check_sync_status():
                error("i18n out of sync - run 'python3 scripts/i18nsync.py sync' first")
            else:
                success("i18n in sync")
                sys.exit(0)
        except SystemExit:
            raise
        except Exception as e:
            error(f"Check failed: {e}")

    elif command == "sync":
        api_token = get_env_or_error('POEDITOR_API_TOKEN')
        project_id = get_env_or_error('POEDITOR_PROJECT_ID')
        prune = "--prune" in sys.argv[2:]
        if prune:
            warn("--prune deletes every POEditor term missing from the local en.json, including its translations.")
            warn("The official plugin checkout is refreshed first, so pruning keeps official plugin terms.")
            warn("dux-qml-common terms are included from the submodule, so pruning keeps them as long as the submodule is current.")
            warn("dms-greeter terms are fetched from POEditor and re-included, so pruning keeps them.")

        common_entries = load_common_entries()
        common_keys = entry_keys(common_entries)
        greeter_entries = load_greeter_entries(api_token, project_id)
        greeter_keys = entry_keys(greeter_entries)

        clone_or_update(OFFICIAL_PLUGINS_REPO, OFFICIAL_PLUGINS_DIR)
        extract_strings()

        current_en = normalize_json(EN_JSON)
        strings_changed = json.dumps(current_en, sort_keys=True) != json.dumps(staged_en(), sort_keys=True)

        last_common_en = {}
        if SYNC_STATE.exists():
            with open(SYNC_STATE) as f:
                last_common_en = json.load(f).get('common_en_json', {})
        common_changed = json.dumps(common_entries, sort_keys=True) != json.dumps(last_common_en, sort_keys=True)

        renames = load_term_renames() if strings_changed else {}
        carry = collect_rename_translations(api_token, project_id, renames)

        if strings_changed or common_changed or prune:
            combined = combine_entries(current_en, common_entries)
            combined = combine_entries(combined, greeter_entries)
            upload_source_strings(api_token, project_id, combined, prune)
            apply_rename_translations(api_token, project_id, carry)
            if renames:
                TERM_RENAMES_JSON.unlink()
        else:
            info("No changes in source strings")

        translations_changed, common_files_changed = download_translations(api_token, project_id, common_keys, greeter_keys)

        if strings_changed or translations_changed:
            subprocess.run(['git', 'add', 'translations/'], cwd=REPO_ROOT)
            save_sync_state()
            success("Sync complete - changes staged for commit")
        else:
            save_sync_state()
            info("Already in sync")

        if common_files_changed:
            info(f"dux-qml-common poexports updated: {', '.join(common_files_changed)}")
            info("Commit those in dux-qml-common and bump the pointer here (make update-common).")

    elif command == "local":
        info("Updating en.json locally (no POEditor sync)")

        old_en = normalize_json(EN_JSON)
        old_terms = {entry['term']: entry for entry in old_en} if isinstance(old_en, list) else {}

        extract_strings()

        new_en = normalize_json(EN_JSON)
        new_terms = {entry['term']: entry for entry in new_en} if isinstance(new_en, list) else {}

        added = set(new_terms.keys()) - set(old_terms.keys())
        removed = set(old_terms.keys()) - set(new_terms.keys())

        if added:
            info(f"\n+{len(added)} new terms:")
            for term in sorted(added)[:20]:
                print(f"  + {term[:60]}...")
            if len(added) > 20:
                print(f"  ... and {len(added) - 20} more")

        if removed:
            info(f"\n-{len(removed)} removed terms:")
            for term in sorted(removed)[:20]:
                print(f"  - {term[:60]}...")
            if len(removed) > 20:
                print(f"  ... and {len(removed) - 20} more")

        success(f"\n✓ {len(new_en)} total terms")

        if not added and not removed:
            info("No changes detected")

    else:
        error(f"Unknown command: {command}")

if __name__ == '__main__':
    main()
