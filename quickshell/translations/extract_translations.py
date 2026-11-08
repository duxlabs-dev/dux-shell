#!/usr/bin/env python3
import ast
import re
import json
from pathlib import Path
from collections import defaultdict


def decode_string_literal(content, quote):
    try:
        return ast.literal_eval(f"{quote}{content}{quote}")
    except (ValueError, SyntaxError):
        return content


def spans_overlap(a, b):
    return a[0] < b[1] and b[0] < a[1]


STR_DQ = r'"((?:\\.|[^"\\])*)"'
STR_SQ = r"'((?:\\.|[^'\\])*)'"


def call_patterns(func, arg_count, trailing_true=False):
    patterns = []
    for lit, quote in ((STR_DQ, '"'), (STR_SQ, "'")):
        args = r'\s*,\s*'.join([lit] * arg_count)
        tail = r'\s*,\s*true\s*\)' if trailing_true else r'\s*\)'
        patterns.append((re.compile(rf'{func}\(\s*{args}{tail}'), quote))
    return patterns


QSTR_PATTERNS = call_patterns(r'qsTr', 1)
# I18n.tr(term, context, true) -- the literal `true` flag uploads the
# context as a real POEditor context, giving (term, context) its own
# translation slot. Must be on one line with a literal `true`.
TR_REAL_CONTEXT_PATTERNS = call_patterns(r'I18n\.tr', 2, trailing_true=True)
TR_CONTEXT_PATTERNS = call_patterns(r'I18n\.tr', 2)
TR_SIMPLE_PATTERNS = call_patterns(r'I18n\.tr', 1)
# I18n.trFor(pluginId, term[, context[, true]]) -- plugin-scoped lookup,
# owned by the DankPlugins POEditor project keyed "<pluginId>:<context>".
TRFOR_REAL_CONTEXT_PATTERNS = call_patterns(r'I18n\.trFor', 3, trailing_true=True)
TRFOR_CONTEXT_PATTERNS = call_patterns(r'I18n\.trFor', 3)
TRFOR_SIMPLE_PATTERNS = call_patterns(r'I18n\.trFor', 2)

# Plugin checkouts under quickshell/: official monorepo terms still use
# I18n.tr and belong to the shell catalog; external plugins are owned by
# the DankPlugins project and never enter the shell catalog.
OFFICIAL_PLUGINS_DIR = 'dms-plugins'
EXTERNAL_PLUGINS_DIR = 'dms-plugins-external'


def new_translation_bucket():
    return {
        'contexts': set(),
        'real_contexts': defaultdict(list),
        'occurrences': [],
        'plain_occurrences': []
    }


def scan_line(line, occ, translations, real_patterns, context_patterns, simple_patterns, key_offset=0):
    real_spans = []
    for pattern, quote in real_patterns:
        for match in pattern.finditer(line):
            key = tuple(decode_string_literal(g, quote) for g in match.groups()[:key_offset])
            term = decode_string_literal(match.group(key_offset + 1), quote)
            context = decode_string_literal(match.group(key_offset + 2), quote)
            translations[key + (term,)]['real_contexts'][context].append(occ)
            translations[key + (term,)]['occurrences'].append(occ)
            real_spans.append(match.span())

    context_spans = []
    for pattern, quote in context_patterns:
        for match in pattern.finditer(line):
            if any(spans_overlap(match.span(), span) for span in real_spans):
                continue
            key = tuple(decode_string_literal(g, quote) for g in match.groups()[:key_offset])
            term = decode_string_literal(match.group(key_offset + 1), quote)
            context = decode_string_literal(match.group(key_offset + 2), quote)
            translations[key + (term,)]['contexts'].add(context)
            translations[key + (term,)]['occurrences'].append(occ)
            translations[key + (term,)]['plain_occurrences'].append(occ)
            context_spans.append(match.span())

    for pattern, quote in simple_patterns:
        for match in pattern.finditer(line):
            if any(spans_overlap(match.span(), span) for span in real_spans + context_spans):
                continue
            key = tuple(decode_string_literal(g, quote) for g in match.groups()[:key_offset])
            term = decode_string_literal(match.group(key_offset + 1), quote)
            translations[key + (term,)]['occurrences'].append(occ)
            translations[key + (term,)]['plain_occurrences'].append(occ)


def extract_qstr_strings(root_dir):
    translations = defaultdict(new_translation_bucket)

    # DCommon terms are owned by the dux-qml-common repo (synced through
    # the DMS POEditor project); rglob not following the symlink is load-bearing.
    for qml_file in Path(root_dir).rglob('*.qml'):
        relative_path = qml_file.relative_to(root_dir)

        # PLUGINS/ holds developer examples demonstrating plugin-local
        # translations; their strings never enter the central catalog.
        if relative_path.parts[0] in ('PLUGINS', EXTERNAL_PLUGINS_DIR):
            continue

        with open(qml_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                occ = {'file': str(relative_path), 'line': line_num}
                for pattern, quote in QSTR_PATTERNS:
                    for match in pattern.finditer(line):
                        term = decode_string_literal(match.group(1), quote)
                        translations[(term,)]['occurrences'].append(occ)
                        translations[(term,)]['plain_occurrences'].append(occ)
                scan_line(line, occ, translations, TR_REAL_CONTEXT_PATTERNS, TR_CONTEXT_PATTERNS, TR_SIMPLE_PATTERNS)

    return {key[0]: data for key, data in translations.items()}


def extract_plugin_strings(checkout):
    checkout = Path(checkout)
    scoped = defaultdict(new_translation_bucket)
    plain = defaultdict(list)

    for qml_file in checkout.rglob('*.qml'):
        relative_path = qml_file.relative_to(checkout)
        with open(qml_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                occ = {'file': f"{checkout.name}/{relative_path}", 'line': line_num}
                scan_line(line, occ, scoped, TRFOR_REAL_CONTEXT_PATTERNS, TRFOR_CONTEXT_PATTERNS, TRFOR_SIMPLE_PATTERNS, key_offset=1)
                shell_terms = defaultdict(new_translation_bucket)
                scan_line(line, occ, shell_terms, TR_REAL_CONTEXT_PATTERNS, TR_CONTEXT_PATTERNS, TR_SIMPLE_PATTERNS)
                for (term,), data in shell_terms.items():
                    plain[term].extend(data['occurrences'])

    return scoped, plain


def area_tags(occurrences):
    tags = set()
    for occ in occurrences:
        path = occ['file']
        if path.startswith(OFFICIAL_PLUGINS_DIR + '/'):
            tags.add('plugin-' + path.split('/')[1].lower())
        elif path.startswith(('Modules/Settings/', 'Modals/Settings/')):
            tags.add('settings')
        else:
            tags.add('shell')
    return sorted(tags)


def references(occurrences):
    return ", ".join(f"{occ['file']}:{occ['line']}" for occ in occurrences)


def create_poeditor_json(translations):
    poeditor_data = []

    for term, data in sorted(translations.items()):
        if data['plain_occurrences']:
            contexts = sorted(data['contexts']) if data['contexts'] else []
            poeditor_data.append({
                "term": term,
                "context": term,
                "reference": references(data['plain_occurrences']),
                "comment": " | ".join(contexts),
                "tags": area_tags(data['plain_occurrences'])
            })

        for context in sorted(data['real_contexts']):
            poeditor_data.append({
                "term": term,
                "context": context,
                "reference": references(data['real_contexts'][context]),
                "comment": "",
                "tags": area_tags(data['real_contexts'][context])
            })

    return poeditor_data


def create_plugin_poeditor_json(scoped):
    entries = []
    for (plugin_id, term), data in sorted(scoped.items()):
        if data['plain_occurrences']:
            entries.append({
                "term": term,
                "context": f"{plugin_id}:{term}",
                "reference": references(data['plain_occurrences']),
                "comment": " | ".join(sorted(data['contexts']))
            })
        for context in sorted(data['real_contexts']):
            entries.append({
                "term": term,
                "context": f"{plugin_id}:{context}",
                "reference": references(data['real_contexts'][context]),
                "comment": ""
            })
    return entries


def split_plugin_context(context):
    plugin_id, sep, rest = context.partition(':')
    if not sep:
        return None, context
    return plugin_id, rest


def create_template_json(translations):
    return [
        {
            "term": entry["term"],
            "translation": "",
            "context": entry["context"],
            "reference": "",
            "comment": entry["comment"]
        }
        for entry in create_poeditor_json(translations)
    ]

def main():
    script_dir = Path(__file__).parent
    root_dir = script_dir.parent
    translations_dir = script_dir

    print("Extracting qsTr() strings from QML files...")
    translations = extract_qstr_strings(root_dir)

    print(f"Found {len(translations)} unique strings")

    poeditor_data = create_poeditor_json(translations)
    en_json_path = translations_dir / 'en.json'
    with open(en_json_path, 'w', encoding='utf-8') as f:
        json.dump(poeditor_data, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f"Created source language file: {en_json_path}")

    template_data = create_template_json(translations)
    template_json_path = translations_dir / 'template.json'
    with open(template_json_path, 'w', encoding='utf-8') as f:
        json.dump(template_data, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f"Created template file: {template_json_path}")

    print("\nSummary:")
    print(f"  - Unique strings: {len(translations)}")
    print(f"  - Total occurrences: {sum(len(data['occurrences']) for data in translations.values())}")
    print(f"  - Strings with contexts: {sum(1 for data in translations.values() if data['contexts'])}")
    print(f"  - Real-context entries: {sum(len(data['real_contexts']) for data in translations.values())}")
    print(f"  - POEditor entries: {len(poeditor_data)}")
    print(f"  - Source file: {en_json_path}")
    print(f"  - Template file: {template_json_path}")

if __name__ == '__main__':
    main()
