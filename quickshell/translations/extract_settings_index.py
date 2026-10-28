#!/usr/bin/env python3
import json
import re
import sys
from collections import Counter
from pathlib import Path

from extract_translations import STR_DQ, STR_SQ, decode_string_literal

ABBREVIATIONS = {
    "on-screen displays": ["osd"],
    "on-screen display": ["osd"],
    "do not disturb": ["dnd"],
    "keyboard shortcuts": ["keybinds", "hotkeys", "bindings", "keys"],
    "notifications": ["notif", "notifs", "alerts"],
    "notification": ["notif", "alert"],
    "wallpaper": ["background", "bg", "image", "picture", "desktop"],
    "transparency": ["opacity", "alpha", "translucent", "transparent"],
    "visibility": ["visible", "hide", "show", "hidden", "autohide", "auto-hide"],
    "temperature": ["temp", "celsius", "fahrenheit"],
    "configuration": ["config", "configure", "setup"],
    "applications": ["apps", "programs"],
    "application": ["app", "program"],
    "animation": ["motion", "transition", "animate", "animations"],
    "typography": ["font", "fonts", "text", "typeface"],
    "workspaces": ["workspace", "desktops", "virtual"],
    "workspace": ["desktop", "virtual"],
    "bluetooth": ["bt"],
    "network": ["wifi", "wi-fi", "ethernet", "internet", "connection", "wireless"],
    "display": ["monitor", "screen", "output"],
    "displays": ["monitors", "screens", "outputs"],
    "brightness": ["bright", "dim", "backlight"],
    "volume": ["audio", "sound", "speaker", "loudness"],
    "battery": ["power", "charge", "charging"],
    "clock": ["time", "watch"],
    "calendar": ["date", "day", "month", "year"],
    "launcher": ["app drawer", "app menu", "start menu", "applications"],
    "dock": ["taskbar", "panel"],
    "bar": ["panel", "taskbar", "topbar", "statusbar"],
    "theme": ["appearance", "look", "style", "colors", "colour"],
    "color": ["colour", "hue", "tint"],
    "colors": ["colours", "palette"],
    "dark": ["night", "dark mode"],
    "light": ["day", "light mode"],
    "lock screen": ["lockscreen", "login", "security"],
    "power": ["shutdown", "reboot", "restart", "suspend", "hibernate", "sleep"],
    "idle": ["afk", "inactive", "timeout", "screensaver"],
    "gamma": ["color temperature", "night light", "blue light", "redshift"],
    "media player": ["mpris", "music", "audio", "playback"],
    "clipboard": ["copy", "paste", "cliphist", "history"],
    "updater": ["updates", "upgrade", "packages"],
    "plugins": ["extensions", "addons", "widgets"],
    "spacing": ["gap", "gaps", "margin", "margins", "padding"],
    "corner": ["corners", "rounded", "radius", "round"],
    "matugen": ["dynamic", "wallpaper colors", "material"],
    "running apps": ["taskbar", "windows", "active", "open"],
    "weather": ["forecast", "temperature", "climate"],
    "sounds": ["audio", "effects", "sfx"],
    "printers": ["print", "cups", "printing"],
    "widgets": ["components", "modules"],
}

CATEGORY_KEYWORDS = {
    "Personalization": ["customize", "custom", "personal", "appearance"],
    "Time & weather": ["clock", "forecast", "date"],
    "Keyboard shortcuts": ["keys", "bindings", "hotkey"],
    "Bar": ["panel", "topbar", "statusbar"],
    "Applications": ["apps", "programs", "window", "rules", "matching", "floating"],
    "Dock": ["taskbar", "launcher bar"],
    "Network": ["connectivity", "online"],
    "System": ["os", "linux"],
    "Launcher": ["start", "menu", "drawer"],
    "Theme & colors": ["appearance", "look", "style", "scheme"],
    "Lock screen": ["security", "login", "password"],
    "Plugins": ["extend", "addon"],
    "About": ["info", "version", "credits", "help"],
    "Fonts & motion": ["fonts", "animation", "text"],
    "Sounds": ["audio", "sfx", "effects"],
    "Media player": ["music", "spotify", "mpris"],
    "Notifications": ["alerts", "messages", "toast"],
    "On-screen displays": ["osd", "indicator", "popup"],
    "Running apps": ["windows", "tasks", "active"],
    "System updater": ["packages", "upgrade"],
    "Power & sleep": ["shutdown", "suspend", "energy"],
    "Displays": ["monitor", "screen", "resolution"],
    "Desktop widgets": ["conky", "desktop clock"],
    "Audio": ["sound", "volume", "speaker", "microphone", "headphones", "pipewire"],
    "Locale": ["locale", "language", "country"],
    "Greeter": ["login", "greetd", "display manager"],
    "Multiplexers": ["tmux", "zellij", "terminal"],
    "Frame": ["window", "border", "decoration"],
    "Dank Island": ["island", "activities", "dynamic island"],
    "Default apps": ["browser", "terminal", "handlers", "mime"],
    "Users": ["accounts", "user", "profile"],
    "Autostart": ["startup", "launch", "boot"],
}

TAB_INDEX_MAP = {
    "TimeWeatherTab.qml": 1,
    "WeatherSettingsTab.qml": 56,
    "KeybindsTab.qml": 2,
    "DBarTab.qml": 3,
    "DDashTab.qml": 43,
    "DigitalWellbeingTab.qml": 67,
    "CompositorLayoutTab.qml": 37,
    "WindowRulesTab.qml": 38,
    "DockGeneralTab.qml": 5,
    "DockWidgetsTab.qml": 57,
    "DockAppearanceTab.qml": 58,
    "DockAdvancedTab.qml": 59,
    "DBarAppearanceTab.qml": 6,
    "DDotTab.qml": 65,
    "NetworkStatusTab.qml": 7,
    "NetworkEthernetTab.qml": 39,
    "NetworkWifiTab.qml": 40,
    "NetworkVpnTab.qml": 41,
    "NetworkCellularTab.qml": 47,
    "PrinterTab.qml": 8,
    "LauncherTab.qml": 9,
    "ThemeColorsTab.qml": 10,
    "ThemeAppsTab.qml": 50,
    "ThemeScheduleTab.qml": 51,
    "WallpaperCyclingTab.qml": 52,
    "ShadowsTab.qml": 53,
    "BarWidgetTab.qml": 54,
    "LockScreenTab.qml": 11,
    "PluginsManageTab.qml": 28,
    "AboutTab.qml": 13,
    "TypographyMotionTab.qml": 14,
    "SoundsTab.qml": 15,
    "MediaPlayerTab.qml": 16,
    "NotificationRulesTab.qml": 55,
    "OSDTab.qml": 18,
    "RunningAppsTab.qml": 19,
    "SoftwareUpdatesTab.qml": 20,
    "ChangelogTab.qml": 66,
    "PowerSleepTab.qml": 21,
    "ClipboardTab.qml": 23,
    "DisplayConfigTab.qml": 24,
    "GammaControlTab.qml": 25,
    "DisplayWidgetsTab.qml": 26,
    "DesktopWidgetsTab.qml": 27,
    "DesktopWidgetTab.qml": 63,
    "AudioTab.qml": 29,
    "LocaleTab.qml": 30,
    "GreeterTab.qml": 31,
    "MuxTab.qml": 32,
    "DefaultAppsTab.qml": 34,
    "UsersTab.qml": 35,
    "UserAccountsTab.qml": 60,
    "CreateUserTab.qml": 61,
    "GreeterAuthTab.qml": 62,
    "PaletteInjectTab.qml": 64,
    "AutoStartTab.qml": 36,
    "BatteryTab.qml": 42,
    "MouseTouchpadTab.qml": 44,
    "KeyboardTab.qml": 45,
}

SIDEBAR_GATE_CONDITIONS = [
    ("shortcutsOnly", "keybindsAvailable"),
    ("soundsOnly", "soundsAvailable"),
    ("cupsOnly", "cupsAvailable"),
    ("greeterOnly", "greeterAvailable"),
    ("dmsOnly", "networkAvailable"),
    ("hyprlandNiriOnly", "isHyprlandOrNiri"),
    ("clipboardOnly", "dmsConnected"),
    ("inputCapable", "inputCapable"),
    ("pointerCapable", "pointerCapable"),
    ("windowRulesCapable", "windowRulesCapable"),
    ("layoutCapable", "layoutCapable"),
    ("cellularOnly", "cellularAvailable"),
]

FILE_PAGE_MAP = {
    "WallpaperColorsTab.qml": "personalization",
    "ThemeSurfacesTab.qml": "theme_surfaces",
    "WidgetsTab.qml": "dankbar_widgets",
    "NotificationsTab.qml": "notifications",
    "UserAccountsTab.qml": "user_accounts",
    "BarHubHeader.qml": "dankbar",
    "DockHubHeader.qml": "dock",
    "PluginsHubHeader.qml": "plugins",
}

TAB_META_DEFAULT = ("Settings", None, None)

# Frame and island rows live on the bar pages; ungated ones still need their feature on.
BAR_TAB_FILES = {"DBarTab.qml", "DBarAppearanceTab.qml"}

SEARCHABLE_COMPONENTS = [
    "SettingsCard",
    "SettingsToggleRow",
    "SettingsDropdownRow",
    "SettingsButtonGroupRow",
    "SettingsSliderRow",
    "SettingsToggleCard",
    "SettingsToggleSliderRow",
    "SettingsSplitRow",
    "SettingsNavRow",
    "SettingsRow",
    "ColorDropdownRow",
]

STOPWORDS = {
    "the",
    "and",
    "for",
    "with",
    "from",
    "this",
    "that",
    "are",
    "was",
    "will",
    "can",
    "has",
    "have",
    "been",
    "when",
    "your",
    "use",
    "used",
    "using",
    "instead",
    "like",
    "such",
    "also",
    "only",
    "which",
    "each",
    "other",
    "some",
    "into",
    "than",
    "then",
    "them",
    "these",
    "those",
}


def alias_keywords(text):
    aliases = set()
    for term in sorted(ABBREVIATIONS, key=len, reverse=True):
        pattern = rf"\b{re.escape(term)}(?:e?s)?\b"
        if not re.search(pattern, text):
            continue
        aliases.update(ABBREVIATIONS[term])
        if " " in term or "-" in term:
            text = re.sub(pattern, " ", text)
    return aliases


def enrich_keywords(label, description, category, existing_tags, parent_label=None):
    keywords = set(existing_tags)

    label_lower = label.lower()
    label_words = re.split(r"[\s\-_&/\"]+", label_lower)
    keywords.update(w for w in label_words if len(w) > 2)
    keywords.update(alias_keywords(label_lower))

    if description:
        desc_lower = description.lower()
        desc_words = re.split(r"[\s\-_&/,.]+", desc_lower)
        keywords.update(w for w in desc_words if len(w) > 3 and w.isalpha())
        keywords.update(alias_keywords(desc_lower))

    for name in (category, parent_label):
        if not name:
            continue
        keywords.update(CATEGORY_KEYWORDS.get(name, []))
        name_lower = name.lower()
        keywords.update(w for w in re.split(r"[\s\-_&/]+", name_lower) if len(w) > 2)
        keywords.update(alias_keywords(name_lower))

    keywords = {k for k in keywords if k not in STOPWORDS and len(k) > 1}
    return sorted(keywords)


def literal_args(value):
    """Extract literal and supported runtime .arg() values from a setting description."""
    call_tail = value.split("I18n.tr(", 1)[-1].split("I18n.tr(", 1)[0]
    args = []
    pattern = r"\.arg\(\s*(?:" + STR_DQ + "|" + STR_SQ + r"|(?P<dynamic>UsersService\.(?:adminGroup|greeterGroup)))?"
    for match in re.finditer(pattern, call_tail):
        if match.group(1) is not None:
            args.append(decode_string_literal(match.group(1), '"'))
        elif match.group(2) is not None:
            args.append(decode_string_literal(match.group(2), "'"))
        elif match.group("dynamic") is not None:
            service, prop = match.group("dynamic").split(".", 1)
            args.append({"service": service, "property": prop})
        else:
            args.append(None)
    return args


def apply_args(text, args):
    for index, arg in enumerate(args, start=1):
        if isinstance(arg, str):
            text = text.replace(f"%{index}", arg)
    return text


def extract_i18n_string(value):
    for literal, quote in ((STR_DQ, '"'), (STR_SQ, "'")):
        match = re.search(rf"I18n\.tr\(\s*{literal}", value) or re.fullmatch(literal, value.strip())
        if match and match.group(1):
            return decode_string_literal(match.group(1), quote)
    return None


def is_status_notice(value):
    """A description with an empty branch only shows while some state holds; it is not searchable text."""
    return re.search(r"""\?\s*(""|'')\s*:|:\s*(""|'')\s*$""", value.strip()) is not None


def extract_tags(value):
    match = re.search(r"\[([^\]]+)\]", value)
    if not match:
        return []
    content = match.group(1)
    tags = re.findall(r'["\']([^"\']+)["\']', content)
    return tags


def parse_component_block(content, start_pos, component_name):
    brace_count = 0
    started = False
    block_start = start_pos

    for i in range(start_pos, len(content)):
        if content[i] == "{":
            if not started:
                block_start = i
                started = True
            brace_count += 1
        elif content[i] == "}":
            brace_count -= 1
            if started and brace_count == 0:
                return content[block_start : i + 1]
    return ""


def extract_property(block, prop_name):
    pattern = rf"\b{prop_name}\s*:\s*([^\n]+)"
    match = re.search(pattern, block)
    if match:
        return match.group(1).strip()
    return None


def own_scope(block):
    """The block with every nested component body removed, so a card without a title does not borrow one from its rows."""
    depth = 0
    kept = []
    for char in block:
        if char == "{":
            depth += 1
            if depth <= 1:
                kept.append(char)
            continue
        if char == "}":
            depth -= 1
            if depth <= 0:
                kept.append(char)
            continue
        if depth <= 1:
            kept.append(char)
    return "".join(kept)


def child_blocks(block):
    children = []
    depth = 0
    i = 0
    while i < len(block):
        char = block[i]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 1:
            match = re.match(r"[A-Z]\w*\s*\{", block[i:])
            if match and (i == 0 or not (block[i - 1].isalnum() or block[i - 1] in "_.")):
                child = parse_component_block(block, i, None)
                children.append(child)
                i = block.index(child, i) + len(child)
                continue
        i += 1
    return children


def borrowed_description(block, setting_key):
    """First description among the nested rows that have no index entry of their own."""
    for child in child_blocks(block):
        own = own_scope(child)
        key = extract_property(own, "settingKey")
        if key and key.strip("\"'") != setting_key:
            continue
        found = extract_property(own, "description") or extract_property(own, "summary") or borrowed_description(child, setting_key)
        if found:
            return found
    return None


def load_wrapper_components(root_dir):
    widgets_dir = Path(root_dir) / "Modules" / "Settings" / "Widgets"
    wrappers = {}

    for qml_file in sorted(widgets_dir.glob("*.qml")):
        if qml_file.stem in SEARCHABLE_COMPONENTS or SHARED_CARD_NAME.fullmatch(qml_file.stem):
            continue

        with open(qml_file, "r", encoding="utf-8") as f:
            content = f.read()

        root_match = re.search(r"^(\w+)\s*\{", content, re.MULTILINE)
        if not root_match or root_match.group(1) not in SEARCHABLE_COMPONENTS:
            continue

        wrappers[qml_file.stem] = {
            prop: extract_property(content, prop)
            for prop in ("settingKey", "title", "text", "description", "iconName", "tags")
        }

    return wrappers


SHARED_CARD_NAME = re.compile(r"Island\w+Card")
SHARED_CARD_PATTERN = re.compile(r"\b(Island\w+Card)\s*\{")
SHARED_CARD_ROW_PATTERN = re.compile(r"\b(?:Settings\w*Row|Loader)\s*\{")


def strip_hidden_rows(card_content, hosted, docked, dot):
    """Drop rows the instance hides for good: `visible: !root.hosted` on a hosted page, `visible: root.docked` on an undocked one, `visible: !root.isDot` on the dot."""
    result = card_content
    for match in reversed(list(SHARED_CARD_ROW_PATTERN.finditer(card_content))):
        block = parse_component_block(card_content, match.start(), "")
        visible = extract_property(block, "visible") or ""
        if (hosted and "!root.hosted" in visible) or (not docked and "root.docked" in visible) or (dot and "!root.isDot" in visible):
            result = result[: match.start()] + result[match.start() + len(block):]
    return result


def inline_shared_cards(root_dir, content):
    """Append each shared island card a page instantiates, with its settingKeys rewritten to the page's keyPrefix."""
    widgets_dir = Path(root_dir) / "Modules" / "Settings" / "Widgets"
    for match in SHARED_CARD_PATTERN.finditer(content):
        card_file = widgets_dir / f"{match.group(1)}.qml"
        if not card_file.exists():
            continue
        instance = parse_component_block(content, match.start(), match.group(1))
        prefix_match = re.search(r'keyPrefix:\s*"(\w+)"', instance)
        prefix = prefix_match.group(1) if prefix_match else "island"
        hosted = "hosted: true" in instance
        docked = "docked: false" not in instance
        dot = "isDot: true" in instance
        card = strip_hidden_rows(card_file.read_text(encoding="utf-8"), hosted, docked, dot)
        content += "\n" + card.replace('settingKey: root.keyPrefix + "', f'settingKey: "{prefix}')
    return content


def find_settings_components(content, filename, wrappers, tab_meta, hub_meta):
    results = []
    file_tab_index = TAB_INDEX_MAP.get(filename, -1)
    file_page = FILE_PAGE_MAP.get(filename)

    if file_tab_index == -1 and not file_page:
        return results

    card_conditions = []

    for component in SEARCHABLE_COMPONENTS + sorted(wrappers):
        defaults = wrappers.get(component, {})
        pattern = rf"\b{component}\s*\{{"
        for match in re.finditer(pattern, content):
            block = parse_component_block(content, match.start(), component)
            if not block:
                continue
            block_end = content.index(block, match.start()) + len(block)

            setting_key = extract_property(block, "settingKey") or defaults.get("settingKey")
            if setting_key:
                setting_key = setting_key.strip("\"'")

            if not setting_key or not re.fullmatch(r"\w+", setting_key):
                continue

            tab_index = file_tab_index

            own = own_scope(block)
            title_raw = extract_property(own, "title") or defaults.get("title")
            text_raw = extract_property(own, "text") or defaults.get("text")
            label = None
            if title_raw:
                label = extract_i18n_string(title_raw)
            if not label and text_raw:
                label = extract_i18n_string(text_raw)
            if not label and component == "SettingsCard":
                page_label = hub_meta.get(file_page) if file_page else tab_meta.get(file_tab_index, TAB_META_DEFAULT)
                label = page_label[0]

            if not label:
                continue

            icon_raw = extract_property(block, "iconName") or defaults.get("iconName")
            icon = None
            if icon_raw:
                icon = icon_raw.strip("\"'")
                if icon.startswith("{") or "?" in icon:
                    icon = None

            tags_raw = extract_property(block, "tags") or defaults.get("tags")
            tags = []
            if tags_raw:
                tags = extract_tags(tags_raw)

            desc_raw = extract_property(own, "description") or extract_property(own, "summary") or defaults.get("description") or borrowed_description(block, setting_key)
            description = None
            description_args = []
            if desc_raw and not is_status_notice(desc_raw):
                description = extract_i18n_string(desc_raw)
                description_args = literal_args(desc_raw)

            visible_raw = extract_property(own_scope(block), "visible")
            page_meta = hub_meta.get(file_page) if file_page else None
            condition_key = page_meta[2] if page_meta else tab_meta.get(tab_index, TAB_META_DEFAULT)[2]
            if visible_raw:
                if filename == "WorkspacesTab.qml" and setting_key == "workspaceFollowFocus":
                    condition_key = "workspaceFollowFocusCapable"
                elif "CompositorService.supportsSmartDock" in visible_raw:
                    condition_key = "smartDockCapable"
                elif "CompositorService.supportsNativeOverview" in visible_raw:
                    condition_key = "nativeOverviewCapable"
                elif "CompositorService.supportsWorkspaceFollowFocus" in visible_raw:
                    condition_key = "workspaceFollowFocusCapable"
                elif "CompositorService.supportsWindowRules" in visible_raw or "CompositorService.supportsBarAutoHideReveal" in visible_raw:
                    condition_key = "windowRulesCapable"
                elif "CompositorService.supportsLayoutConfig" in visible_raw:
                    condition_key = "layoutCapable"
                elif "CompositorService.supportsPointerConfig" in visible_raw:
                    condition_key = "pointerCapable"
                elif "CompositorService.supportsInputConfig" in visible_raw:
                    condition_key = "inputCapable"
                elif "CompositorService.isAqueous" in visible_raw:
                    if "CompositorService.isHyprland" in visible_raw:
                        condition_key = "smartDockCapable"
                    elif "CompositorService.isNiri" in visible_raw:
                        condition_key = "nativeOverviewCapable"
                    else:
                        condition_key = "isAqueous"
                elif all(c in visible_raw for c in ("CompositorService.isNiri", "CompositorService.isHyprland", "CompositorService.isMango")):
                    condition_key = "windowRulesCapable"
                elif all(c in visible_raw for c in ("CompositorService.isNiri", "CompositorService.isHyprland")):
                    condition_key = "isHyprlandOrNiri"
                elif all(c in visible_raw for c in ("CompositorService.isNiri", "CompositorService.isMango")):
                    condition_key = "isNiriOrMango"
                elif "CompositorService.isNiri" in visible_raw:
                    condition_key = "isNiri"
                elif "CompositorService.isHyprland" in visible_raw:
                    condition_key = "isHyprland"
                elif "CompositorService.isMango" in visible_raw:
                    condition_key = "isMango"
                elif "KeybindsService.available" in visible_raw:
                    condition_key = "keybindsAvailable"
                elif "MultimediaService.unavailable" in visible_raw:
                    condition_key = "soundsAvailable"
                elif "CupsService.cupsAvailable" in visible_raw:
                    condition_key = "cupsAvailable"
                elif "NetworkService.networkAvailable" in visible_raw:
                    condition_key = "networkAvailable"
                elif "DMSService.isConnected" in visible_raw:
                    condition_key = "dmsConnected"
                elif "Theme.matugenAvailable" in visible_raw:
                    condition_key = "matugenAvailable"
                elif "dock.config.enabled" in visible_raw:
                    condition_key = "dockEnabled"
                elif "selectedIslandDocked" in visible_raw or "!root.selectedIslandFree" in visible_raw:
                    condition_key = "islandDocked"
                elif "selectedIslandFree" in visible_raw and "!dankBarTab.selectedIslandFree" not in visible_raw:
                    condition_key = "islandFree"
            if filename in BAR_TAB_FILES and not condition_key:
                if setting_key.startswith("frame"):
                    condition_key = "frameEnabled"
                elif setting_key.startswith("island"):
                    condition_key = "islandEnabled"
            if filename == "DDotTab.qml" and not condition_key and setting_key != "dotEnabled":
                condition_key = "dotEnabled"
            if component == "SettingsCard":
                card_conditions.append((match.start(), block_end, condition_key if extract_property(own, "visible") else None))
            elif not condition_key:
                condition_key = next((cond for start, end, cond in card_conditions if start < match.start() < end), None)

            category, parent_label, _ = page_meta if page_meta else tab_meta.get(tab_index, TAB_META_DEFAULT)
            enriched_keywords = enrich_keywords(label, apply_args(description, description_args) if description else description, category, tags, parent_label)

            entry = {
                "section": setting_key,
                "label": label,
                "tabIndex": tab_index,
                "category": category,
                "keywords": enriched_keywords,
            }

            if file_page:
                entry["page"] = file_page
            if parent_label:
                entry["parentLabel"] = parent_label
            if icon:
                entry["icon"] = icon
            if description:
                entry["description"] = description
            if description_args and None not in description_args:
                entry["descriptionArgs"] = description_args
            if condition_key:
                entry["conditionKey"] = condition_key

            results.append(entry)

    return results


def match_bracket(content, start, open_char, close_char):
    depth = 0
    for i in range(start, len(content)):
        if content[i] == open_char:
            depth += 1
        elif content[i] == close_char:
            depth -= 1
            if depth == 0:
                return i
    return -1


def split_objects(array_body):
    objects = []
    i = 0
    while i < len(array_body):
        if array_body[i] != "{":
            i += 1
            continue
        end = match_bracket(array_body, i, "{", "}")
        if end == -1:
            break
        objects.append(array_body[i : end + 1])
        i = end + 1
    return objects


def string_prop(block, name):
    match = re.search(rf'"{name}"\s*:\s*"([^"]*)"', block)
    return match.group(1) if match else None


def i18n_prop(block, name):
    match = re.search(rf'"{name}"\s*:\s*([^\n]+)', block)
    return extract_i18n_string(match.group(1)) if match else None


def gate_condition(block):
    for qml_flag, key in SIDEBAR_GATE_CONDITIONS:
        if f'"{qml_flag}": true' in block:
            return key
    return None


def parse_structure_entry(block, parent=None):
    own = block
    children_raw = ""
    children_match = re.search(r'"children"\s*:\s*\[', block)
    if children_match:
        end = match_bracket(block, children_match.end() - 1, "[", "]")
        children_raw = block[children_match.end() : end]
        own = block[: children_match.start()] + block[end + 1 :]

    tab_index_match = re.search(r'"tabIndex"\s*:\s*(\d+)', own)
    label = i18n_prop(own, "text")
    entry = {
        "id": string_prop(own, "id"),
        "label": label,
        "runtimeLabel": label is None and re.search(r'"text"\s*:', own) is not None,
        "icon": string_prop(own, "icon"),
        "tabIndex": int(tab_index_match.group(1)) if tab_index_match else None,
        "hint": i18n_prop(own, "hint"),
        "separator": '"separator": true' in own,
        "conditionKey": gate_condition(own) or (parent["conditionKey"] if parent else None),
        "parentLabel": parent["label"] if parent else None,
        "own": own,
        "children": [],
    }
    entry["children"] = [parse_structure_entry(child, entry) for child in split_objects(children_raw)]
    return entry


def parse_structure(sidebar_file):
    with open(sidebar_file, "r", encoding="utf-8") as f:
        content = f.read()
    start = content.find("structure: [")
    if start == -1:
        return []
    array_start = content.index("[", start)
    array_end = match_bracket(content, array_start, "[", "]")
    return [parse_structure_entry(block) for block in split_objects(content[array_start + 1 : array_end])]


def flatten_leaves(entries):
    leaves = []
    for entry in entries:
        if entry["separator"]:
            continue
        if entry["tabIndex"] is not None:
            leaves.append(entry)
        leaves.extend(flatten_leaves(entry["children"]))
    return leaves


def leaf_category(leaf):
    if leaf["label"]:
        return leaf["label"], leaf["parentLabel"]
    return leaf["parentLabel"] or "Settings", None


def build_tab_meta(leaves):
    return {leaf["tabIndex"]: leaf_category(leaf) + (leaf["conditionKey"],) for leaf in leaves}


def hubs_of(entries):
    return [entry for entry in entries if entry["label"] and not entry["separator"] and (entry["children"] or entry["tabIndex"] is None)]


def build_hub_meta(hubs):
    return {hub["id"]: (hub["label"], None, hub["conditionKey"]) for hub in hubs}


def generate_hub_entries(hubs):
    entries = []
    for hub in hubs:
        child_labels = [child["label"] for child in hub["children"] if child["label"]]
        keywords = set(enrich_keywords(hub["label"], " ".join(child_labels + [hub["hint"] or ""]), hub["label"], []))
        for child_label in child_labels:
            keywords.update(w for w in re.split(r"[\s\-_&/]+", child_label.lower()) if len(w) > 2)
        entry = {
            "section": f"_hub_{hub['id']}",
            "label": hub["label"],
            "tabIndex": hub["tabIndex"] if hub["tabIndex"] is not None else -1,
            "page": hub["id"],
            "category": hub["label"],
            "keywords": sorted(k for k in keywords if k not in STOPWORDS),
            "icon": hub["icon"],
        }
        if hub["hint"]:
            entry["description"] = hub["hint"]
        if hub["conditionKey"]:
            entry["conditionKey"] = hub["conditionKey"]
        entries.append(entry)
    return entries


def generate_tab_entries(leaves, settings_entries):
    highlightable_labels = {
        (entry["tabIndex"], entry["label"])
        for entry in settings_entries
        if not str(entry["section"]).startswith("_tab_")
    }
    label_counts = Counter(leaf["label"] for leaf in leaves if leaf["label"])

    entries = []
    for leaf in leaves:
        base_label = leaf["label"] or ""
        if leaf["children"] or not (base_label or leaf["runtimeLabel"]):
            continue
        label = (
            f"{leaf['parentLabel']}: {base_label}"
            if label_counts[base_label] > 1 and leaf["parentLabel"]
            else base_label
        )
        if (leaf["tabIndex"], label) in highlightable_labels:
            continue

        category, parent_label = leaf_category(leaf)
        entry = {
            "section": f"_tab_{leaf['tabIndex']}",
            "label": label,
            "tabIndex": leaf["tabIndex"],
            "category": category,
            "keywords": enrich_keywords(base_label, leaf["hint"], category, [], parent_label),
            "icon": leaf["icon"],
        }
        if parent_label:
            entry["parentLabel"] = parent_label
        if leaf["hint"]:
            entry["description"] = leaf["hint"]
        if leaf["conditionKey"]:
            entry["conditionKey"] = leaf["conditionKey"]
        if leaf["runtimeLabel"]:
            entry["runtimeType"] = "pageLabel"
        entries.append(entry)

    return entries


def extract_settings_index(root_dir, tab_meta, hub_meta):
    settings_dir = Path(root_dir) / "Modules" / "Settings"
    wrappers = load_wrapper_components(root_dir)
    all_entries = []
    seen_keys = set()

    for qml_file in sorted(settings_dir.glob("*.qml")):
        if qml_file.name not in TAB_INDEX_MAP and qml_file.name not in FILE_PAGE_MAP:
            continue

        with open(qml_file, "r", encoding="utf-8") as f:
            content = inline_shared_cards(root_dir, f.read())

        entries = find_settings_components(content, qml_file.name, wrappers, tab_meta, hub_meta)
        for entry in entries:
            key = entry["section"]
            if key not in seen_keys:
                seen_keys.add(key)
                all_entries.append(entry)

    if "windowRules" not in seen_keys:
        category, parent_label, _ = tab_meta.get(38, TAB_META_DEFAULT)
        all_entries.append(
            {
                "section": "windowRules",
                "label": "Window Rules",
                "tabIndex": 38,
                "category": category,
                "parentLabel": parent_label,
                "keywords": enrich_keywords(
                    "Window Rules",
                    "Define compositor rules for window behavior",
                    category,
                    ["matching", "floating", "fullscreen", "opacity"],
                    parent_label,
                ),
                "icon": "select_window",
                "description": "Define compositor rules for window behavior",
                "conditionKey": "windowRulesCapable",
            }
        )

    if "islandHomeLayout" not in seen_keys:
        category, parent_label, _ = tab_meta.get(3, TAB_META_DEFAULT)
        all_entries.append(
            {
                "section": "islandHomeLayout",
                "label": "Home Layout",
                "tabIndex": 3,
                "category": category,
                "parentLabel": parent_label,
                "keywords": enrich_keywords(
                    "Home Layout",
                    "Order and hide the groups around the island clock",
                    category,
                    ["media", "launcher", "weather", "battery", "volume", "brightness", "notifications", "badge", "left", "right", "hidden", "reorder"],
                    parent_label,
                ),
                "icon": "home",
                "description": "Order and hide the groups around the island clock",
                "conditionKey": "islandEnabled",
            }
        )

    for entry in all_entries:
        if entry.get("parentLabel") is None:
            entry.pop("parentLabel", None)

    return all_entries


OPTION_LABEL_PATTERN = re.compile(r'\b(?:text|title):\s*I18n\.tr\("((?:[^"\\]|\\.)*)"')


def extract_bar_widget_option_labels(root_dir):
    options_dir = Path(root_dir) / "Modules" / "Settings" / "BarWidgetOptions"
    entries = []
    for qml_file in sorted(options_dir.glob("*Options.qml")):
        labels = []
        for label in OPTION_LABEL_PATTERN.findall(inline_shared_cards(root_dir, qml_file.read_text(encoding="utf-8"))):
            if not label or label in labels:
                continue
            labels.append(label)
            entries.append(
                {
                    "section": f"barWidgetOption:{qml_file.name}:{len(labels)}",
                    "label": label,
                    "tabIndex": 22,
                    "keywords": [],
                    "runtimeType": "barWidgetOption",
                    "optionFile": qml_file.name,
                }
            )
    return entries


def validate(all_entries, leaves, hubs, sidebar_file, root_dir):
    errors = []
    settings_dir = root_dir / "Modules" / "Settings"
    hub_ids = {hub["id"] for hub in hubs}
    for hub in hubs:
        header = string_prop(hub["own"], "hubHeader")
        if header and not (settings_dir / f"{header}.qml").exists():
            errors.append(f"{hub['id']}: hubHeader '{header}' has no Modules/Settings/{header}.qml")
    for page in FILE_PAGE_MAP.values():
        if page not in hub_ids:
            errors.append(f"FILE_PAGE_MAP page '{page}' is not a hub")
    seen_ids = Counter()
    for hub in hubs:
        seen_ids[hub["id"]] += 1
        for alias in re.findall(r'"([^"]+)"', (re.search(r'"aliases"\s*:\s*\[([^\]]*)\]', hub["own"]) or [None, ""])[1]):
            seen_ids[alias] += 1
    for leaf in leaves:
        if leaf["children"]:
            continue
        seen_ids[leaf["id"]] += 1
    for page_id, count in seen_ids.items():
        if count > 1:
            errors.append(f"page id '{page_id}' is declared {count} times")
    for tab_file in sorted(settings_dir.glob("*Tab.qml")):
        if tab_file.name not in TAB_INDEX_MAP and tab_file.name not in FILE_PAGE_MAP:
            errors.append(f"{tab_file.name} missing from TAB_INDEX_MAP")

    with open(sidebar_file, "r", encoding="utf-8") as f:
        sidebar_content = f.read()
    sidebar_tabs = {leaf["tabIndex"] for leaf in leaves}
    file_backed_tabs = {leaf["tabIndex"] for leaf in leaves if not leaf["children"]}
    mapped_tabs = set(TAB_INDEX_MAP.values())
    for tab_index in sorted(file_backed_tabs - mapped_tabs):
        errors.append(f"tabIndex {tab_index} in sidebar has no file in TAB_INDEX_MAP")
    with open(Path(__file__).parent / "en.json", "r", encoding="utf-8") as f:
        catalog_terms = {entry["term"] for entry in json.load(f)}
    known_labels = catalog_terms | set(re.findall(r'I18n\.tr\("([^"]+)"', sidebar_content))
    service_file = root_dir / "Services" / "SettingsSearchService.qml"
    with open(service_file, "r", encoding="utf-8") as f:
        condition_keys = set(re.findall(r'"(\w+)":\s*\(\)\s*=>', f.read()))

    for entry in all_entries:
        page = entry.get("page")
        if page and page not in hub_ids:
            errors.append(f"{entry['section']}: page '{page}' is not a hub")
        if entry["tabIndex"] == -1 and not page:
            errors.append(f"{entry['section']}: tabIndex -1 without a page")
        if entry["tabIndex"] != -1 and entry["tabIndex"] not in sidebar_tabs:
            errors.append(f"{entry['section']}: tabIndex {entry['tabIndex']} not in sidebar")
        for field in ("category", "parentLabel"):
            value = entry.get(field)
            if value and value not in known_labels:
                errors.append(f"{entry['section']}: {field} '{value}' is not a catalog term")
        cond = entry.get("conditionKey")
        if cond and cond not in condition_keys:
            errors.append(f"{entry['section']}: unknown conditionKey '{cond}'")

    if not errors:
        return
    for error in sorted(set(errors)):
        print(f"error: {error}", file=sys.stderr)
    sys.exit(1)


def main():
    script_dir = Path(__file__).parent
    root_dir = script_dir.parent
    sidebar_file = root_dir / "Common" / "SettingsTabs.qml"

    print("Extracting settings search index...")
    structure = parse_structure(sidebar_file)
    leaves = flatten_leaves(structure)
    hubs = hubs_of(structure)
    tab_meta = build_tab_meta(leaves)
    hub_meta = build_hub_meta(hubs)
    settings_entries = extract_settings_index(root_dir, tab_meta, hub_meta)
    tab_entries = generate_tab_entries(leaves, settings_entries) + generate_hub_entries(hubs)

    option_entries = extract_bar_widget_option_labels(root_dir)

    all_entries = tab_entries + settings_entries + option_entries

    all_entries.sort(key=lambda x: (x["tabIndex"], x["label"], x["section"]))
    validate(all_entries, leaves, hubs, sidebar_file, root_dir)

    output_path = script_dir / "settings_search_index.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_entries, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Found {len(settings_entries)} searchable settings")
    print(f"Found {len(tab_entries)} tab entries")
    print(f"Found {len(option_entries)} bar widget option labels")
    print(f"Total: {len(all_entries)} entries")
    print(f"Output: {output_path}")

    conditions = set()
    for entry in all_entries:
        if "conditionKey" in entry:
            conditions.add(entry["conditionKey"])

    if conditions:
        print(f"Condition keys found: {', '.join(sorted(conditions))}")


if __name__ == "__main__":
    main()
