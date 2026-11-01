# Dux Shell Translations

This directory contains translation files for Dux Shell extracted from all qsTr() calls in the QML codebase.

## Files

- **en.json** - Source language file with English strings and file references
- **template.json** - Empty template for creating new translations
- **extract_translations.py** - Script to regenerate translation files

## POEditor Format

The JSON files follow POEditor's import format:

```json
[
  {
    "term": "string to translate",
    "context": "file:line",
    "reference": "Modules/Settings/AboutTab.qml:45",
    "comment": ""
  }
]
```

### Field Descriptions

- **term**: The source string in English (from qsTr() calls)
- **context**: Primary location where the string appears (file:line)
- **reference**: All locations where this string is used (comma-separated)
- **comment**: Additional notes for translators (currently empty)

## How to Create a New Translation

1. Copy `template.json` to your language code (e.g., `es.json` for Spanish)
2. Fill in the `translation` field for each entry:
   ```json
   {
     "term": "Settings",
     "translation": "Configuración",
     "context": "Modals/Settings/SettingsModal.qml:147",
     "reference": "Modals/Settings/SettingsModal.qml:147",
     "comment": ""
   }
   ```
3. Import to POEditor or use directly in your translation workflow

## Regenerating Translation Files

To update the translation files after code changes:

```bash
cd /home/brandon/.config/quickshell/DankMaterialShellGit/translations
./extract_translations.py
```

This will scan all QML files and regenerate `en.json` and `template.json`.

## Notes

- Strings are deduplicated - if the same string appears in multiple locations, references are merged
- File paths are relative to the project root
- Line numbers are preserved for accurate context
- Empty strings and comments are reserved for translator notes
