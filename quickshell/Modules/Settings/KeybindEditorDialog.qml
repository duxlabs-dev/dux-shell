pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/KeyUtils.js" as KeyUtils
import "../../Common/KeybindActions.js" as Actions

DDialog {
    id: root

    readonly property var log: Log.scoped("KeybindEditorDialog")

    property var bindData: ({})
    property bool isNew: false
    property bool readOnly: false
    property bool busy: false
    property var panelWindow: null

    property bool recording: false
    property int editingKeyIndex: -1
    property bool addingNewKey: false
    property string editKey: ""
    property string editAction: ""
    property string editDesc: ""
    property int editCooldownMs: 0
    property string editFlags: ""
    property bool editAllowWhenLocked: false
    property var editRepeat: undefined
    property var editAllowInhibiting: undefined
    property string editTrigger: ""
    property string editReleaseAction: ""
    property var editPassThrough: undefined
    property var _loneModifiers: []
    property bool hasChanges: false
    property bool useCustomCompositor: false
    property bool _altShiftGhost: false

    readonly property var keys: bindData.keys || []
    readonly property var editingKey: keys[editingKeyIndex] ?? null
    readonly property string originalKey: editingKey?.key ?? ""
    readonly property string actionType: Actions.getActionType(editAction)
    readonly property string actionLabel: KeybindsService.getActionLabel(editAction) || I18n.tr("Select", "verb, dropdown placeholder or option that opens a picker") + "…"
    readonly property var configConflict: bindData.conflict || null
    readonly property var conflicts: editKey ? KeyUtils.getConflictingBinds(editKey, bindData.action, KeybindsService.getFlatBinds(), KeybindsService.modKey, KeybindsService.modSymbol) : []
    readonly property string editKeysym: KeyUtils.keyFromToken(editKey)
    readonly property bool keysymUnreachable: KeyUtils.keysymUnreachable(editKeysym, KeybindsService.firstLevelKeymap)
    readonly property bool canReset: !isNew && !readOnly && editingKey?.isOverride === true && editingKey?.hasDefault === true
    readonly property bool canSave: !readOnly && editKey !== "" && Actions.isValidAction(editAction)
    readonly property bool canSubmit: canSave && (isNew || hasChanges) && !busy
    readonly property bool formEnabled: !readOnly
    readonly property bool wideForm: actionWidth + padding * 2 >= maximumWidth

    readonly property var argConfig: Actions.getActionArgConfig(KeybindsService.currentProvider, editAction)
    readonly property var dmsParsedArgs: argConfig?.type === "dms" ? Actions.parseDmsActionArgs(editAction) : null
    readonly property var dmsArgDefs: dmsParsedArgs?.base ? (Actions.getDmsActionArgs()[dmsParsedArgs.base]?.args ?? []) : []
    readonly property var dmsFlagArgs: dmsArgDefs.filter(arg => arg.type === "flag")
    readonly property bool showDmsArgs: actionType === "dms" && argConfig?.type === "dms"
    readonly property bool showCompositorPicker: actionType === "compositor" && !useCustomCompositor
    readonly property var compositorParsedArgs: Actions.parseCompositorActionArgs(KeybindsService.currentProvider, editAction)
    readonly property var compositorArgDefs: argConfig?.config?.args ?? []
    readonly property var compositorFlags: compositorFlagOptions()
    readonly property var bindOptionList: bindOptions()
    readonly property bool isNiri: KeybindsService.currentProvider === "niri"
    readonly property bool showReleaseOption: isNiri && editTrigger !== "both" && !KeyUtils.isScrollTrigger(editKey)
    readonly property bool showPassThroughOption: isNiri && KeyUtils.isKeyboardTrigger(editKey)
    readonly property bool effectivePassThrough: editPassThrough ?? editTrigger === "release"

    readonly property string customCategory: I18n.tr("Custom")
    readonly property string repeatTooltip: I18n.tr("Repeats while the key is held", "keybind option tooltip")
    readonly property string lockedTooltip: I18n.tr("Also works on the lock screen", "keybind option tooltip")
    readonly property string pointerTooltip: I18n.tr("Includes the mouse pointer", "keybind screenshot option tooltip")
    readonly property string saveTooltip: I18n.tr("Also saves the screenshot to disk", "keybind screenshot option tooltip")

    readonly property var typeTooltips: ({
            "dms": I18n.tr("DMS shell actions (launcher, clipboard, etc.)"),
            "compositor": I18n.tr("Compositor actions (focus, move, etc.)", "keybind action type tooltip"),
            "spawn": I18n.tr("Run a program (e.g., firefox, kitty)"),
            "shell": I18n.tr("Run a shell command (e.g., notify-send)")
        })

    signal saveRequested(string originalKey, var data)
    signal resetRequested(string key)

    embedded: false
    opened: false
    maximumWidth: SettingsMetrics.formDialogWidth
    surfaceColor: Theme.hostSurface
    title: isNew ? I18n.tr("Add shortcut", "keybind editor dialog title and button") : I18n.tr("Edit shortcut", "keybind editor dialog title")
    closeEnabled: !busy
    acceptEnabled: canSubmit
    onAccepted: save()

    function present(bind, keyIndex, newBind) {
        // Needed to tell a key the layout cannot reach from one it can, and
        // the layout may have changed since the editor was last open.
        KeybindsService.loadFirstLevelKeymap();
        recording = false;
        bindData = bind;
        isNew = newBind;
        loadKey(keyIndex);
        opened = true;
        forceActiveFocus();
    }

    function loadKey(index) {
        const key = keys[index] ?? null;
        addingNewKey = false;
        editingKeyIndex = key ? index : -1;
        editKey = key?.key ?? "";
        editAction = bindData.action || "";
        editDesc = key?.desc || bindData.desc || "";
        editCooldownMs = key?.cooldownMs || 0;
        editFlags = key?.flags || "";
        editAllowWhenLocked = key?.allowWhenLocked || false;
        editRepeat = key?.repeat;
        editAllowInhibiting = key?.allowInhibiting;
        editTrigger = key?.trigger || "";
        editReleaseAction = key?.releaseAction || "";
        editPassThrough = key?.passThrough;
        useCustomCompositor = actionType === "compositor" && editAction !== "" && !KeybindsService.isKnownCompositorAction(editAction);
        hasChanges = false;
    }

    function startAddingNewKey() {
        if (readOnly) {
            KeybindsService.showHyprlandReadOnlyWarning();
            return;
        }
        addingNewKey = true;
        editingKeyIndex = -1;
        editKey = "";
        hasChanges = true;
    }

    function changedFrom(key) {
        if (editKey !== (key?.key ?? ""))
            return true;
        if (editAction !== (bindData.action || ""))
            return true;
        if (editDesc !== (key?.desc || bindData.desc || ""))
            return true;
        if (editCooldownMs !== (key?.cooldownMs || 0))
            return true;
        if (editFlags !== (key?.flags || ""))
            return true;
        if (editAllowWhenLocked !== (key?.allowWhenLocked || false))
            return true;
        if (editTrigger !== (key?.trigger || "") || editReleaseAction !== (key?.releaseAction || "") || editPassThrough !== key?.passThrough)
            return true;
        return editRepeat !== key?.repeat || editAllowInhibiting !== key?.allowInhibiting;
    }

    function updateEdit(changes) {
        if (readOnly)
            return;
        if (changes.key !== undefined) {
            editKey = changes.key;
            if (KeyUtils.isScrollTrigger(editKey))
                editTrigger = "";
            if (!KeyUtils.isKeyboardTrigger(editKey))
                editPassThrough = undefined;
        }
        if (changes.action !== undefined)
            editAction = changes.action;
        if (changes.desc !== undefined)
            editDesc = changes.desc;
        if (changes.cooldownMs !== undefined)
            editCooldownMs = changes.cooldownMs;
        if (changes.flags !== undefined)
            editFlags = changes.flags;
        if (changes.allowWhenLocked !== undefined)
            editAllowWhenLocked = changes.allowWhenLocked;
        // undefined is a real value here: it restores the compositor default
        if ("repeat" in changes)
            editRepeat = changes.repeat;
        if ("allowInhibiting" in changes)
            editAllowInhibiting = changes.allowInhibiting;
        if (changes.trigger !== undefined)
            editTrigger = changes.trigger;
        if ("passThrough" in changes)
            editPassThrough = changes.passThrough;
        hasChanges = addingNewKey || changedFrom(editingKey);
    }

    function selectType(type) {
        if (readOnly || type === actionType)
            return;
        switch (type) {
        case "dms":
            updateEdit({
                "action": KeybindsService.dmsActions[0].id,
                "desc": KeybindsService.dmsActions[0].label
            });
            return;
        case "compositor":
            useCustomCompositor = false;
            updateEdit({
                "action": "close-window",
                "desc": "Close Window"
            });
            return;
        case "spawn":
            updateEdit({
                "action": "spawn ",
                "desc": ""
            });
            return;
        case "shell":
            updateEdit({
                "action": "spawn sh -c \"\"",
                "desc": ""
            });
            return;
        }
    }

    function typeLabel(type) {
        switch (type) {
        case "dms":
            return "DMS";
        case "compositor":
            return I18n.tr("Compositor");
        case "spawn":
            return I18n.tr("Command");
        case "shell":
            return I18n.tr("Shell", "noun, keybind editor field label for a shell command");
        }
        return type;
    }

    function selectCompositorCategory(category) {
        if (category === customCategory) {
            useCustomCompositor = true;
            return;
        }
        if (!useCustomCompositor)
            return;
        useCustomCompositor = false;
        const first = KeybindsService.getCompositorActions(category)[0];
        if (!first)
            return;
        updateEdit({
            "action": first.id,
            "desc": first.label
        });
    }

    function save() {
        if (readOnly) {
            KeybindsService.showHyprlandReadOnlyWarning();
            return;
        }
        if (!canSubmit)
            return;
        recording = false;
        const data = {
            "key": editKey,
            "action": editAction,
            "desc": editDesc,
            "cooldownMs": editCooldownMs,
            "flags": editFlags,
            "allowWhenLocked": editAllowWhenLocked,
            "repeat": editRepeat,
            "allowInhibiting": editAllowInhibiting
        };
        if (isNiri) {
            data.trigger = editTrigger;
            data.releaseAction = editReleaseAction;
            data.passThrough = editPassThrough;
        }
        saveRequested(addingNewKey ? "" : originalKey, data);
    }

    function startRecording() {
        if (readOnly) {
            KeybindsService.showHyprlandReadOnlyWarning();
            return;
        }
        _loneModifiers = [];
        recording = true;
    }

    function stopRecording() {
        _loneModifiers = [];
        recording = false;
    }

    function captureKey(event) {
        if (KeyUtils.modifierFromQtKey(event.key)) {
            if (isNiri)
                _loneModifiers = KeyUtils.heldModifiers(event.key, event.modifiers, _loneModifiers);
            return;
        }
        switch (event.key) {
        // lock keys are toggles; NumLock picks the numpad keysym (KP_7 vs KP_Home) and must not become the bind
        case Qt.Key_NumLock:
        case Qt.Key_CapsLock:
        case Qt.Key_ScrollLock:
            return;
        }

        if (event.key === 0 && (event.modifiers & Qt.AltModifier)) {
            _altShiftGhost = true;
            if (_loneModifiers.length)
                _loneModifiers = KeyUtils.heldModifiers(Qt.Key_Shift, event.modifiers, _loneModifiers);
            return;
        }
        _loneModifiers = [];

        const mods = KeyUtils.modsFromEvent(event.modifiers);

        if (_altShiftGhost && (event.modifiers & Qt.AltModifier) && !mods.includes("Shift"))
            mods.push("Shift");
        _altShiftGhost = false;

        const token = KeyUtils.chordToken(event.key, event.modifiers, mods, event.nativeScanCode, KeybindsService.modKey, KeybindsService.modSymbol);
        if (!token) {
            log.warn("Unknown key:", event.key, "mods:", event.modifiers);
            return;
        }

        updateEdit({
            "key": token
        });
        stopRecording();
    }

    // A lone modifier binds release-only so its chords keep working.
    function captureKeyRelease(event) {
        if (_loneModifiers.length === 0 || !KeyUtils.modifierFromQtKey(event.key))
            return;
        const token = KeyUtils.bareModifierToken(_loneModifiers, KeybindsService.modKey, KeybindsService.modSymbol);
        updateEdit({
            "key": token,
            "trigger": "release",
            "repeat": undefined
        });
        stopRecording();
    }

    function captureWheel(wheel) {
        let mods = [];
        if (wheel.modifiers & Qt.ControlModifier)
            mods.push("Ctrl");
        if (wheel.modifiers & Qt.ShiftModifier)
            mods.push("Shift");
        if (wheel.modifiers & Qt.AltModifier)
            mods.push("Alt");
        if (wheel.modifiers & Qt.MetaModifier)
            mods.push("Super");
        mods = KeyUtils.withSymbolicMod(mods, KeybindsService.modKey, KeybindsService.modSymbol);

        const wheelKey = wheelKeyName(wheel.angleDelta);
        if (!wheelKey)
            return;
        updateEdit({
            "key": KeyUtils.formatToken(mods, wheelKey)
        });
        stopRecording();
    }

    function wheelKeyName(delta) {
        if (delta.y > 0)
            return "WheelScrollUp";
        if (delta.y < 0)
            return "WheelScrollDown";
        if (delta.x > 0)
            return "WheelScrollRight";
        if (delta.x < 0)
            return "WheelScrollLeft";
        return "";
    }

    function setDmsArgs(changes) {
        if (!dmsParsedArgs)
            return;
        const args = Object.assign({}, dmsParsedArgs.args, changes);
        updateEdit({
            "action": Actions.buildDmsAction(dmsParsedArgs.base, args)
        });
    }

    function commitDmsAmount(text) {
        if (!dmsParsedArgs)
            return;
        const oldAction = editAction;
        const args = Object.assign({}, dmsParsedArgs.args, {
            "amount": text || "5"
        });
        const newAction = Actions.buildDmsAction(dmsParsedArgs.base, args);
        const changes = {
            "action": newAction
        };
        if (editDesc === "" || editDesc === KeybindsService.getActionLabel(oldAction))
            changes.desc = KeybindsService.getActionLabel(newAction);
        updateEdit(changes);
    }

    function dashTabLabel(tab) {
        switch (tab) {
        case "media":
            return I18n.tr("Media");
        case "wallpaper":
            return I18n.tr("Wallpaper");
        case "weather":
            return I18n.tr("Weather");
        default:
            return I18n.tr("Overview");
        }
    }

    function dashTabValue(label) {
        switch (label) {
        case I18n.tr("Media"):
            return "media";
        case I18n.tr("Wallpaper"):
            return "wallpaper";
        case I18n.tr("Weather"):
            return "weather";
        default:
            return "";
        }
    }

    function dmsFlagLabel(name) {
        switch (name) {
        case "no-file":
            return I18n.tr("Save");
        case "no-clipboard":
            return I18n.tr("Clipboard");
        case "clipboard-file":
            return I18n.tr("Copy path");
        case "cursor":
            return I18n.tr("Pointer");
        default:
            return name;
        }
    }

    function dmsFlagTooltip(name) {
        switch (name) {
        case "no-file":
            return saveTooltip;
        case "no-clipboard":
            return I18n.tr("Copies the screenshot to the clipboard", "keybind screenshot option tooltip");
        case "clipboard-file":
            return I18n.tr("Copies the saved file too, so terminals paste its path", "keybind screenshot option tooltip");
        case "cursor":
            return pointerTooltip;
        default:
            return "";
        }
    }

    function dmsFlagChecked(flag) {
        const set = dmsParsedArgs?.args[flag.name] === true;
        return flag.inverted ? !set : set;
    }

    function setDmsFlag(flag, checked) {
        const changes = {};
        changes[flag.name] = flag.inverted ? !checked : checked;
        setDmsArgs(changes);
    }

    function compositorCategory() {
        const base = editAction.split(" ")[0];
        const categories = KeybindsService.getCompositorCategories();
        for (const category of categories) {
            if (KeybindsService.getCompositorActions(category).some(action => action.id === base))
                return category;
        }
        return categories[0] || "Window";
    }

    function showArgEditor(index, argDef) {
        if (!argDef)
            return false;
        if (argDef.type !== "text" && argDef.type !== "number")
            return false;
        if (KeybindsService.currentProvider === "mangowc")
            return true;
        return index === 0;
    }

    function displayArgValue(argDef) {
        if (!argDef || !compositorParsedArgs?.args)
            return "";
        const value = compositorParsedArgs.args[argDef.name];
        if (value === undefined || value === null)
            return "";
        if (argDef.emptyValue !== undefined && value === argDef.emptyValue)
            return "";
        return String(value);
    }

    function commitArgValue(argDef, textValue) {
        if (!argDef || !argConfig)
            return;
        const args = Object.assign({}, compositorParsedArgs?.args || {});
        args[argDef.name] = textValue;
        updateEdit({
            "action": Actions.buildCompositorAction(KeybindsService.currentProvider, compositorParsedArgs?.base || argConfig.base, args)
        });
    }

    function compositorFlagOptions() {
        const base = argConfig?.base ?? "";
        switch (base) {
        case "move-column-to-workspace":
        case "move-column-to-workspace-down":
        case "move-column-to-workspace-up":
            return [
                {
                    "label": I18n.tr("Follow focus"),
                    "value": "focus",
                    "tooltip": I18n.tr("Moves focus along with the column", "keybind option tooltip, niri move column to workspace")
                }
            ];
        case "quit":
            return [
                {
                    "label": I18n.tr("Skip confirmation"),
                    "value": "skip-confirmation"
                }
            ];
        }
        if (!base.startsWith("screenshot"))
            return [];
        const options = [];
        if (base !== "screenshot-window")
            options.push({
                "label": I18n.tr("Pointer", "noun, mouse cursor, keybind screenshot option to include it"),
                "value": "show-pointer",
                "tooltip": pointerTooltip
            });
        if (base !== "screenshot")
            options.push({
                "label": I18n.tr("Save"),
                "value": "write-to-disk",
                "tooltip": saveTooltip
            });
        return options;
    }

    function compositorFlagSelected() {
        const args = compositorParsedArgs?.args ?? {};
        return compositorFlags.filter(flag => {
            if (flag.value === "focus")
                return args.focus !== false;
            return args[flag.value] === true;
        }).map(flag => flag.value);
    }

    function setCompositorFlag(name, checked) {
        const base = argConfig?.base;
        if (!base)
            return;
        updateEdit({
            "action": compositorFlagAction(base, name, checked)
        });
    }

    function compositorFlagAction(base, name, checked) {
        const provider = KeybindsService.currentProvider;
        if (name === "skip-confirmation")
            return Actions.buildCompositorAction(provider, "quit", checked ? {
                "skip-confirmation": true
            } : {});
        if (name === "focus") {
            const focusArgs = {};
            if (base === "move-column-to-workspace")
                focusArgs.index = compositorParsedArgs?.args?.index || "";
            if (!checked)
                focusArgs.focus = false;
            return Actions.buildCompositorAction(provider, base, focusArgs);
        }
        const args = Object.assign({}, compositorParsedArgs?.args || {});
        args[name] = checked;
        return Actions.buildCompositorAction(provider, compositorParsedArgs?.base || base, args);
    }

    function niriBindOptions() {
        const options = [];
        if (showReleaseOption)
            options.push({
                "label": I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release"),
                "value": "release",
                "tooltip": I18n.tr("Triggers when the key is released", "keybind option tooltip, hyprland release flag")
            });
        if (editTrigger !== "release")
            options.push({
                "label": I18n.tr("Repeat"),
                "value": "repeat",
                "tooltip": repeatTooltip
            });
        options.push({
            "label": I18n.tr("When locked"),
            "value": "locked",
            "tooltip": lockedTooltip
        }, {
            "label": I18n.tr("Inhibitable", "adjective, niri keybind option, apps may inhibit this shortcut"),
            "value": "inhibit",
            "tooltip": I18n.tr("Apps that capture the keyboard can block it", "keybind option tooltip, niri allow inhibiting")
        });
        if (showPassThroughOption)
            options.push({
                "label": I18n.tr("Non-consuming", "adjective, hyprland bind flag toggle, key is not swallowed"),
                "value": "passthrough",
                "tooltip": I18n.tr("The key also reaches the focused window", "keybind option tooltip, hyprland non-consuming flag")
            });
        return options;
    }

    function bindOptions() {
        switch (KeybindsService.currentProvider) {
        case "niri":
            return niriBindOptions();
        case "hyprland":
            return [
                {
                    "label": I18n.tr("Repeat", "noun, keybind option, action repeats while key is held"),
                    "value": "e",
                    "tooltip": repeatTooltip
                },
                {
                    "label": I18n.tr("Locked", "adjective, hyprland bind flag toggle, bind works on lock screen"),
                    "value": "l",
                    "tooltip": lockedTooltip
                },
                {
                    "label": I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release"),
                    "value": "r",
                    "tooltip": I18n.tr("Triggers when the key is released", "keybind option tooltip, hyprland release flag")
                },
                {
                    "label": I18n.tr("Long press"),
                    "value": "o",
                    "tooltip": I18n.tr("Triggers after holding the key", "keybind option tooltip, hyprland long press flag")
                },
                {
                    "label": I18n.tr("Non-consuming", "adjective, hyprland bind flag toggle, key is not swallowed"),
                    "value": "n",
                    "tooltip": I18n.tr("The key also reaches the focused window", "keybind option tooltip, hyprland non-consuming flag")
                },
                {
                    "label": I18n.tr("Mouse", "hyprland bind flag toggle, bind for a mouse button"),
                    "value": "m",
                    "tooltip": I18n.tr("Binds a mouse button, such as mouse:272", "keybind option tooltip, hyprland mouse flag")
                },
                {
                    "label": I18n.tr("Transparent", "adjective, hyprland bind flag toggle"),
                    "value": "t",
                    "tooltip": I18n.tr("Other binds cannot shadow it", "keybind option tooltip, hyprland transparent flag")
                },
                {
                    "label": I18n.tr("Ignore mods", "hyprland bind flag toggle, ignore modifier keys"),
                    "value": "i",
                    "tooltip": I18n.tr("Fires with any modifiers held", "keybind option tooltip, hyprland ignore mods flag")
                },
                {
                    "label": I18n.tr("All submaps", "hyprland bind flag toggle, submap universal"),
                    "value": "u",
                    "tooltip": I18n.tr("Works in every submap", "keybind option tooltip, hyprland submap universal flag")
                },
                {
                    "label": I18n.tr("Auto-consuming", "adjective, hyprland bind flag toggle"),
                    "value": "a",
                    "tooltip": I18n.tr("Consumes the key only when a dispatcher runs", "keybind option tooltip, hyprland auto-consuming flag")
                },
                {
                    "label": I18n.tr("Input capture", "hyprland bind flag toggle, allow input capture"),
                    "value": "x",
                    "tooltip": I18n.tr("Fires even while an input capture session is active", "keybind option tooltip, hyprland allow input capture flag")
                },
                {
                    "label": I18n.tr("Not inhibitable", "adjective, hyprland bind flag toggle, dont_inhibit"),
                    "value": "p",
                    "tooltip": I18n.tr("Fires even when an app inhibits shortcuts", "keybind option tooltip, hyprland dont inhibit flag")
                },
                {
                    "label": I18n.tr("Click", "hyprland bind flag toggle, mouse click bind"),
                    "value": "c",
                    "tooltip": I18n.tr("Triggers on release if the pointer stayed put", "keybind option tooltip, hyprland click flag")
                },
                {
                    "label": I18n.tr("Drag", "hyprland bind flag toggle, mouse drag bind"),
                    "value": "g",
                    "tooltip": I18n.tr("Triggers on release after the pointer moved", "keybind option tooltip, hyprland drag flag")
                }
            ];
        }
        return [];
    }

    function selectedBindOptions() {
        if (KeybindsService.currentProvider === "hyprland")
            return editFlags.split("");
        const selected = [];
        if (editTrigger === "release")
            selected.push("release");
        if (editRepeat !== false)
            selected.push("repeat");
        if (editAllowWhenLocked)
            selected.push("locked");
        if (editAllowInhibiting !== false)
            selected.push("inhibit");
        if (effectivePassThrough)
            selected.push("passthrough");
        return selected;
    }

    function setBindOption(value, checked) {
        switch (value) {
        case "release":
            updateEdit({
                "trigger": checked ? "release" : "",
                "repeat": undefined
            });
            return;
        case "passthrough":
            // niri forwards release-only binds by default, so only write a differing value
            updateEdit({
                "passThrough": checked === (editTrigger === "release") ? undefined : checked
            });
            return;
        case "repeat":
            updateEdit({
                "repeat": checked ? undefined : false
            });
            return;
        case "locked":
            updateEdit({
                "allowWhenLocked": checked
            });
            return;
        case "inhibit":
            updateEdit({
                "allowInhibiting": checked ? undefined : false
            });
            return;
        }
        const flags = editFlags.split("").filter(flag => flag !== value);
        if (checked)
            flags.push(value);
        updateEdit({
            "flags": flags.join("")
        });
    }

    ShortcutInhibitor {
        window: root.panelWindow
        enabled: root.recording
    }

    Binding {
        target: keyChips
        property: "currentIndex"
        value: root.addingNewKey ? -1 : root.editingKeyIndex
    }

    Binding {
        target: dmsActionDropdown
        property: "currentValue"
        value: root.actionLabel
    }

    Binding {
        target: compositorCategoryDropdown
        property: "currentValue"
        value: root.useCustomCompositor ? root.customCategory : root.compositorCategory()
    }

    Binding {
        target: compositorActionDropdown
        property: "currentValue"
        value: root.actionLabel
    }

    Binding {
        target: dashTabDropdown
        property: "currentValue"
        value: root.dashTabLabel(root.dmsParsedArgs?.args?.tab || "")
    }

    actions: [
        DButton {
            text: I18n.tr("Reset to default")
            visible: root.canReset
            enabled: !root.busy
            variant: "text"
            onClicked: root.resetRequested(root.originalKey)
        },
        DButton {
            text: I18n.tr("Cancel")
            enabled: root.closeEnabled
            variant: "text"
            onClicked: root.rejected()
        },
        DButton {
            text: root.isNew ? I18n.tr("Add") : I18n.tr("Save")
            visible: !root.readOnly
            enabled: root.canSubmit
            busy: root.busy
            onClicked: root.save()
        }
    ]

    SettingsGroup {
        visible: root.configConflict !== null

        SettingsRow {
            iconName: "warning"
            title: I18n.tr("This bind is overridden by %1", "keybind conflict notice, %1 is the compositor config file").arg("config.kdl")
            subtitle: I18n.tr("Config action: %1", "keybind conflict notice, %1 is the action from the compositor config").arg(root.configConflict?.action ?? "") + "\n" + I18n.tr("To use this DMS bind, remove or change the keybind in your %1", "keybind conflict hint, %1 is the compositor config file").arg("config.kdl")
        }
    }

    SettingsCard {
        title: I18n.tr("Key", "noun, keybind editor row label for the key combination")
        enabled: root.formEnabled
        headerActions: DButton {
            visible: !root.isNew && !root.readOnly && !root.addingNewKey
            text: I18n.tr("New key")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            variant: "text"
            onClicked: root.startAddingNewKey()
        }

        SettingsRow {
            visible: !root.isNew && (root.keys.length > 1 || root.addingNewKey)

            body: DFilterChips {
                id: keyChips
                width: parent.width
                showCounts: false
                model: root.keys.map(key => ({
                            "label": key.key
                        }))
                onSelectionChanged: index => root.loadKey(index)
            }
        }

        SettingsRow {
            body: Column {
                width: parent.width
                spacing: Theme.spacingS

                FocusScope {
                    id: captureScope

                    readonly property bool rootRecording: root.recording

                    width: parent.width
                    height: Theme.iconButtonSize
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Key", "noun, keybind editor row label for the key combination")
                    Accessible.description: captureHint.visible ? captureHint.text : root.editKey
                    Accessible.onPressAction: root.startRecording()

                    onRootRecordingChanged: {
                        if (rootRecording)
                            forceActiveFocus();
                    }

                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.stopRecording();
                    }

                    Keys.onPressed: event => {
                        if (!root.recording)
                            return;
                        event.accepted = true;
                        root.captureKey(event);
                    }

                    Keys.onReleased: event => {
                        if (!root.recording)
                            return;
                        event.accepted = true;
                        root.captureKeyRelease(event);
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadiusXS
                        color: "transparent"
                        border.color: root.recording ? Theme.primary : Theme.outline
                        border.width: root.recording ? Theme.outlineWidthFocused : Theme.outlineWidth
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.recording ? Qt.CrossCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (!root.recording)
                                root.startRecording();
                        }
                        onWheel: wheel => {
                            if (!root.recording) {
                                wheel.accepted = false;
                                return;
                            }
                            wheel.accepted = true;
                            root.captureWheel(wheel);
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: recordButton.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingM

                        DIcon {
                            name: "keyboard"
                            size: Theme.iconSize
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DKeycap {
                            text: root.editKey
                            visible: root.editKey !== "" && !root.recording
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: captureHint
                            text: root.recording ? I18n.tr("Press key...") : I18n.tr("Click to capture")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            visible: root.editKey === "" || root.recording
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    DActionButton {
                        id: recordButton
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        focusPolicy: Qt.TabFocus
                        iconName: root.recording ? "close" : "radio_button_checked"
                        iconColor: root.recording ? Theme.error : Theme.primary
                        tooltipText: root.recording ? I18n.tr("Stop") : I18n.tr("Record", "verb, tooltip on button that captures a key combination")
                        onClicked: root.recording ? root.stopRecording() : root.startRecording()
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.conflicts.length > 0

                    DIcon {
                        id: conflictIcon
                        name: "warning"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }

                    StyledText {
                        width: parent.width - conflictIcon.width - parent.spacing
                        text: I18n.tr("Conflicts with: %1", "keybind warning, %1 is a list of conflicting bind descriptions").arg(root.conflicts.map(bind => bind.desc).join(", "))
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primary
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignLeft
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.keysymUnreachable

                    DIcon {
                        id: unreachableIcon
                        name: "warning"
                        size: Theme.iconSizeSmall
                        color: Theme.error
                    }

                    StyledText {
                        width: parent.width - unreachableIcon.width - parent.spacing
                        text: I18n.tr("Your keyboard layout puts %1 above the first level, so this bind will never fire. Pick a key the layout types without an extra layer.", "keybind warning, %1 is a key name such as bracketleft").arg(root.editKeysym)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Action")
        enabled: root.formEnabled

        SettingsRow {
            body: DButtonGroup {
                arrowKeysSelect: false
                width: parent.width
                fillWidth: true
                maximumWidth: width
                buttonPadding: Theme.spacingM
                checkEnabled: false
                iconOnly: !root.wideForm
                model: KeybindsService.actionTypes.map(type => ({
                            "text": root.typeLabel(type.id),
                            "icon": root.wideForm ? "" : type.icon,
                            "tooltip": root.typeTooltips[type.id]
                        }))
                currentIndex: KeybindsService.actionTypes.findIndex(type => type.id === root.actionType)
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        root.selectType(KeybindsService.actionTypes[index].id);
                }
            }
        }

        SettingsRow {
            visible: root.actionType === "dms"

            body: DDropdown {
                id: dmsActionDropdown
                width: parent.width
                compactMode: true
                enableFuzzySearch: true
                options: KeybindsService.getDmsActions().map(action => action.label)
                onValueChanged: value => {
                    const action = KeybindsService.getDmsActions().find(entry => entry.label === value);
                    if (!action)
                        return;
                    root.updateEdit({
                        "action": action.id,
                        "desc": KeybindsService.getActionLabel(action.id)
                    });
                }
            }
        }

        SettingsRow {
            visible: root.actionType === "compositor"

            body: Row {
                width: parent.width
                spacing: Theme.spacingS

                DDropdown {
                    id: compositorCategoryDropdown
                    width: Math.round((parent.width - parent.spacing) / 3)
                    compactMode: true
                    options: KeybindsService.getCompositorCategories().concat([root.customCategory])
                    onValueChanged: value => root.selectCompositorCategory(value)
                }

                DDropdown {
                    id: compositorActionDropdown
                    visible: !root.useCustomCompositor
                    width: parent.width - compositorCategoryDropdown.width - parent.spacing
                    compactMode: true
                    enableFuzzySearch: true
                    options: KeybindsService.getCompositorActions(compositorCategoryDropdown.currentValue).map(action => action.label)
                    onValueChanged: value => {
                        const action = KeybindsService.getCompositorActions(compositorCategoryDropdown.currentValue).find(entry => entry.label === value);
                        if (!action)
                            return;
                        root.updateEdit({
                            "action": action.id,
                            "desc": action.label
                        });
                    }
                }

                DTextField {
                    visible: root.useCustomCompositor
                    width: parent.width - compositorCategoryDropdown.width - parent.spacing
                    outlined: true
                    placeholderText: KeybindsService.currentProvider === "hyprland" ? I18n.tr("e.g., hl.dsp.focus({ workspace = \"3\" })") : I18n.tr("e.g., focus-workspace 3, resize-column -10")
                    text: root.actionType === "compositor" ? root.editAction : ""
                    onTextChanged: {
                        if (root.actionType !== "compositor")
                            return;
                        root.updateEdit({
                            "action": text
                        });
                    }
                }
            }
        }

        SettingsRow {
            visible: root.actionType === "spawn"

            body: DTextField {
                readonly property var parsedCommand: root.actionType === "spawn" ? Actions.parseSpawnCommand(root.editAction) : null

                width: parent.width
                outlined: true
                leftIconName: "terminal"
                labelText: I18n.tr("Command")
                placeholderText: I18n.tr("e.g., firefox, kitty --title foo")
                text: parsedCommand ? (parsedCommand.command + " " + parsedCommand.args.join(" ")).trim() : ""
                onTextChanged: {
                    if (root.actionType !== "spawn")
                        return;
                    const parts = text.trim().split(" ").filter(part => part);
                    root.updateEdit({
                        "action": "spawn " + parts.join(" ")
                    });
                }
            }
        }

        SettingsRow {
            visible: root.actionType === "shell"

            body: DTextField {
                width: parent.width
                outlined: true
                leftIconName: "terminal"
                labelText: I18n.tr("Shell", "noun, keybind editor field label for a shell command")
                placeholderText: I18n.tr("e.g., notify-send 'Hello' && sleep 1")
                text: root.actionType === "shell" ? Actions.parseShellCommand(root.editAction) : ""
                onTextChanged: {
                    if (root.actionType !== "shell")
                        return;
                    root.updateEdit({
                        "action": Actions.buildShellAction(KeybindsService.currentProvider, text, Actions.getShellFromAction(root.editAction))
                    });
                }
            }
        }

        SettingsRow {
            visible: root.showDmsArgs && root.dmsArgDefs.some(arg => arg.name === "amount")

            body: DTextField {
                id: amountField

                readonly property string amount: root.dmsParsedArgs?.args?.amount || ""

                width: parent.width
                outlined: true
                leftIconName: "tune"
                labelText: I18n.tr("Amount", "keybind editor field, numeric amount argument of a dms action")
                placeholderText: "5"
                rightAccessoryWidth: amountUnit.width + Theme.spacingS
                onAmountChanged: {
                    if (text !== amount)
                        text = amount;
                }
                Component.onCompleted: text = amount
                onEditingFinished: root.commitDmsAmount(text)

                FieldUnit {
                    id: amountUnit
                    field: amountField
                    text: "%"
                }
            }
        }

        SettingsRow {
            visible: root.showDmsArgs && root.dmsArgDefs.some(arg => arg.name === "device")

            body: DTextField {
                readonly property string device: root.dmsParsedArgs?.args?.device || ""

                width: parent.width
                outlined: true
                leftIconName: "devices"
                labelText: I18n.tr("Device")
                placeholderText: I18n.tr("leave empty for default")
                onDeviceChanged: {
                    if (text !== device)
                        text = device;
                }
                Component.onCompleted: text = device
                onEditingFinished: root.setDmsArgs({
                    "device": text
                })
            }
        }

        SettingsRow {
            visible: root.showDmsArgs && root.dmsArgDefs.some(arg => arg.name === "tab")
            title: I18n.tr("Tab", "noun, keybind argument label for a dashboard tab")

            DDropdown {
                id: dashTabDropdown
                compactMode: true
                options: [I18n.tr("Overview"), I18n.tr("Media"), I18n.tr("Wallpaper"), I18n.tr("Weather")]
                onValueChanged: value => root.setDmsArgs({
                        "tab": root.dashTabValue(value)
                    })
            }
        }

        SettingsRow {
            visible: root.showDmsArgs && root.dmsFlagArgs.length > 0

            body: DFilterChips {
                width: parent.width
                multiSelect: true
                showCounts: false
                model: root.dmsFlagArgs.map(flag => ({
                            "label": root.dmsFlagLabel(flag.name),
                            "value": flag.name,
                            "tooltip": root.dmsFlagTooltip(flag.name)
                        }))
                selectedValues: root.dmsFlagArgs.filter(flag => root.dmsFlagChecked(flag)).map(flag => flag.name)
                onSelectionToggled: (index, selected) => root.setDmsFlag(root.dmsFlagArgs[index], selected)
            }
        }

        Repeater {
            model: root.showCompositorPicker ? root.compositorArgDefs.length : 0

            delegate: SettingsRow {
                id: argRow

                required property int index
                readonly property var argDef: root.compositorArgDefs[index] ?? null

                visible: root.showArgEditor(index, argDef)

                body: DTextField {
                    id: argField

                    property bool syncing: false
                    readonly property string actionValue: root.displayArgValue(argRow.argDef)

                    function syncFromAction() {
                        if (text === actionValue)
                            return;
                        syncing = true;
                        text = actionValue;
                        syncing = false;
                    }

                    width: parent.width
                    outlined: true
                    leftIconName: "tune"
                    labelText: I18n.tr(argRow.argDef?.label || "", "keybind option label")
                    placeholderText: I18n.tr(argRow.argDef?.placeholder || "", "keybind option placeholder")
                    onActionValueChanged: syncFromAction()
                    Component.onCompleted: syncFromAction()
                    onTextChanged: {
                        if (!syncing)
                            root.commitArgValue(argRow.argDef, text);
                    }
                }
            }
        }

        SettingsRow {
            visible: root.showCompositorPicker && root.compositorFlags.length > 0

            body: DFilterChips {
                width: parent.width
                multiSelect: true
                showCounts: false
                model: root.compositorFlags
                selectedValues: root.compositorFlagSelected()
                onSelectionToggled: (index, selected) => root.setCompositorFlag(root.compositorFlags[index].value, selected)
            }
        }

        SettingsRow {
            visible: root.editTrigger === "both"
            title: I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release")
            subtitle: KeybindsService.getActionLabel(root.editReleaseAction) || root.editReleaseAction
        }

        SettingsRow {
            body: DTextField {
                width: parent.width
                outlined: true
                leftIconName: "title"
                labelText: I18n.tr("Title")
                placeholderText: I18n.tr("Hotkey overlay title (optional)")
                text: root.editDesc
                onTextChanged: root.updateEdit({
                    "desc": text
                })
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Options")
        enabled: root.formEnabled
        visible: KeybindsService.currentProvider === "niri" || KeybindsService.currentProvider === "hyprland"

        SettingsRow {
            body: DFilterChips {
                width: parent.width
                multiSelect: true
                showCounts: false
                model: root.bindOptionList
                selectedValues: root.selectedBindOptions()
                onSelectionToggled: (index, selected) => root.setBindOption(root.bindOptionList[index].value, selected)
            }
        }

        SettingsRow {
            visible: KeybindsService.currentProvider === "niri"

            body: DTextField {
                id: cooldownField

                readonly property int cooldownMs: root.editCooldownMs

                width: parent.width
                outlined: true
                leftIconName: "timer"
                labelText: I18n.tr("Cooldown", "noun, niri keybind cooldown time field label")
                placeholderText: "0"
                rightAccessoryWidth: cooldownUnit.width + Theme.spacingS
                onCooldownMsChanged: {
                    const newText = cooldownMs > 0 ? String(cooldownMs) : "";
                    if (text !== newText)
                        text = newText;
                }
                Component.onCompleted: text = cooldownMs > 0 ? String(cooldownMs) : ""
                onTextChanged: {
                    const value = parseInt(text) || 0;
                    if (value !== root.editCooldownMs)
                        root.updateEdit({
                            "cooldownMs": value
                        });
                }

                FieldUnit {
                    id: cooldownUnit
                    field: cooldownField
                    text: I18n.tr("ms", "milliseconds unit suffix after a number field")
                }
            }
        }
    }

    component FieldUnit: StyledText {
        required property DTextField field

        anchors.right: parent.right
        anchors.rightMargin: field.contentPadding
        y: field.containerTop + (field.containerHeight - height) / 2
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
    }
}
