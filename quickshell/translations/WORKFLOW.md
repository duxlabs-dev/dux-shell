# Translation Workflow for Dux Shell

## POEditor Integration Guide

### Initial Setup

1. **Create POEditor Project**
   - Go to https://poeditor.com
   - Create new project "Dux Shell"
   - Add languages you want to support (es, fr, de, etc.)

2. **Import Source Strings**
   - Upload `en.json` as the source language
   - POEditor will detect 336 translatable strings
   - Format: Key-Value JSON

### Translation Workflow

#### Method 1: Using POEditor (Recommended)

1. **Upload source file**
   ```bash
   # Upload en.json to POEditor
   ```

2. **Translate in POEditor**
   - Use POEditor's web interface
   - Invite translators
   - Track progress per language

3. **Export translations**
   ```bash
   # Download from POEditor as JSON
   # Save to translations/{language_code}.json
   # Example: translations/es.json, translations/fr.json
   ```

4. **Test translations**
   ```bash
   # Set your locale and restart shell
   export LANG=es_ES.UTF-8
   qs -p .
   ```

#### Method 2: Manual Translation

1. **Copy template**
   ```bash
   cp translations/template.json translations/es.json
   ```

2. **Fill in translations**
   ```json
   {
     "term": "Settings",
     "context": "Modals/Settings/SettingsModal.qml:147",
     "reference": "Modals/Settings/SettingsModal.qml:147",
     "comment": "",
     "translation": "Configuración"
   }
   ```

3. **Upload to POEditor** (optional)

### Updating Translations After Code Changes

1. **Re-extract strings**
   ```bash
   cd translations
   python3 extract_translations.py
   ```

2. **Upload updated en.json to POEditor**
   - POEditor will detect new/removed strings
   - Preserves existing translations

3. **Download updated translations**

### Translation File Format

POEditor-compatible JSON format:

```json
[
  {
    "term": "source string in English",
    "context": "file:line where it appears",
    "reference": "full/path/to/file.qml:123",
    "comment": "optional context for translators",
    "translation": "translated string"
  }
]
```

### Supported Languages

The shell will auto-detect your system locale. Supported format:
- `es.json` → Spanish (es_ES, es_MX, etc.)
- `fr.json` → French (fr_FR, fr_CA, etc.)
- `de.json` → German
- `zh.json` → Chinese
- `ja.json` → Japanese
- `pt.json` → Portuguese
- etc.

### Testing Translations

1. **Change system locale**
   ```bash
   export LANG=es_ES.UTF-8
   export LC_ALL=es_ES.UTF-8
   ```

2. **Restart shell**
   ```bash
   qs -p .
   ```

3. **Verify translations appear correctly**

### File Structure

```
translations/
├── en.json              # Source language (English)
├── template.json        # Empty template for new languages
├── es.json              # Spanish translation
├── fr.json              # French translation
├── extract_translations.py  # Auto-extraction script
├── README.md            # Technical documentation
└── WORKFLOW.md          # This file
```

### Translation Statistics

- **Total strings:** 336 unique terms
- **Most translated components:**
  - Settings UI: 202 strings (60%)
  - Weather: 25 strings (7%)
  - System monitors: Various
  - Modals: 43 strings (13%)

### POEditor API Integration (Advanced)

For automated sync, use POEditor's API:

```bash
# Export from POEditor
curl -X POST https://api.poeditor.com/v2/projects/export \
  -d api_token="YOUR_TOKEN" \
  -d id="PROJECT_ID" \
  -d language="es" \
  -d type="key_value_json"

# Import to POEditor
curl -X POST https://api.poeditor.com/v2/projects/upload \
  -d api_token="YOUR_TOKEN" \
  -d id="PROJECT_ID" \
  -d updating="terms_translations" \
  -d language="es" \
  -F file=@"translations/es.json"
```

### Best Practices

1. **Context matters:** Use the reference field to understand where strings appear
2. **Test before committing:** Always test translations in the actual UI
3. **Keep synchronized:** Re-extract after significant UI changes
4. **Preserve formatting:** Keep placeholders like `%1`, `{0}` intact
5. **Cultural adaptation:** Some strings may need cultural context, not just literal translation

### Troubleshooting

**Translations not loading?**
- Check file exists: `~/.config/dms/translations/{language_code}.json`
- Verify JSON syntax: `python3 -m json.tool translations/es.json`
- Check console for errors: `qs -v -p .`

**Wrong language loading?**
- Check system locale: `echo $LANG`
- Verify file naming: Must match locale prefix (es_ES → es.json)

**Missing strings?**
- Re-run extraction: `python3 extract_translations.py`
- Compare with en.json to find new strings
