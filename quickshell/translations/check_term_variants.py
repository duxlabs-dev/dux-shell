#!/usr/bin/env python3
"""Block near-variant translation terms (case/trailing-punctuation duplicates).

Unlike a term freeze, new terms are always allowed. This only fails when two
terms collapse to the same string after lowercasing and stripping trailing
".:?! " punctuation - e.g. "Signal" vs "Signal:", "Reset to Default?" vs
"Reset to default". Build punctuation outside tr() instead:
    I18n.tr("Signal") + ":"

"Term" vs "Term..." pairs are NOT flagged: a trailing ellipsis is meaningful
(progress states, opens-a-dialog affordances).
"""
import sys
from collections import defaultdict

from extract_translations import extract_qstr_strings
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent

EXTERNAL_PLUGIN_PREFIX = "dms-plugins-external/"

# Intentional pairs that survive normalization on purpose.
ALLOWED = [
    {"PIN", "Pin"},            # WPS PIN acronym vs the verb "pin"
    {"Device", "device"},      # label vs inline generic-noun fallback
    {"Until %1", "until %1"},  # sentence-initial vs mid-sentence position
    {"Up", "up"},              # scroll direction vs uptime prefix
    {"New", "new"},            # create action vs lowercase plugin recency badge
    {"Custom Color", "Custom color"},  # dms-plugins checkout, not this repo
    {"Media Player", "Media player"},  # dms-plugins checkout, not this repo
]


def normalize(term):
    t = term.replace("…", "...")
    ellipsis = t.rstrip().endswith("...")
    t = t.lower().rstrip(".:?! ")
    return t + "..." if ellipsis else t


def owned_occurrences(data):
    return [occ for occ in data["occurrences"]
            if not occ["file"].startswith(EXTERNAL_PLUGIN_PREFIX)]


def main():
    extracted = extract_qstr_strings(ROOT_DIR)
    translations = {}
    for term, data in extracted.items():
        occurrences = owned_occurrences(data)
        if occurrences:
            translations[term] = occurrences

    groups = defaultdict(set)
    for term in translations:
        groups[normalize(term)].add(term)

    failures = []
    for variants in groups.values():
        if len(variants) < 2 or any(variants == a for a in ALLOWED):
            continue
        # term vs term+"..." is allowed; flag only same-ellipsis-class variants
        plain = {v for v in variants if not v.replace("…", "...").rstrip().endswith("...")}
        dotted = variants - plain
        for cls in (plain, dotted):
            if len(cls) > 1:
                failures.append(sorted(cls))

    if not failures:
        print(f"No term variants ({len(translations)} terms checked)")
        return 0

    print("Near-variant terms found - reuse one exact term (or add to ALLOWED "
          "in check_term_variants.py if genuinely intentional):", file=sys.stderr)
    for variants in sorted(failures):
        print(f"  {variants}", file=sys.stderr)
        for v in variants:
            for occ in translations[v][:3]:
                print(f"      {v!r}: {occ['file']}:{occ['line']}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
