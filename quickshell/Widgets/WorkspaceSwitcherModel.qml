import QtQuick
import Quickshell
import Quickshell.WindowManager
import qs.Common
import qs.Services
import "../Common/WorkspaceModel.js" as WorkspaceModel
import "../DCommon/Common/WheelInput.js" as WheelInput

// Workspace list, focus and switching for one screen, shared by every host that draws workspace indicators.
QtObject {
    id: root

    property string screenName: ""
    property var screen: null
    property bool followFocus: false
    property bool occupiedOnly: false
    property bool showAllTags: false
    property bool showPadding: false
    property int paddingCount: 0
    property bool showSpecial: false
    property bool reverseScrolling: false

    readonly property bool useAqueous: CompositorService.isAqueous && AqueousService.available && Quickshell.env("DMS_FORCE_EXTWS") !== "1"
    readonly property bool useExtWorkspace: {
        if (useAqueous)
            return false;
        if (Quickshell.env("DMS_FORCE_EXTWS") === "1")
            return (WindowManager.windowsets?.length ?? 0) > 0;
        if (!CompositorService.compositorDetected || CompositorService.hasWorkspaceIpc)
            return false;
        return (WindowManager.windowsets?.length ?? 0) > 0;
    }
    readonly property bool useNativeWorkspaces: useAqueous || (!useExtWorkspace && CompositorService.hasWorkspaceIpc)
    readonly property var extProjection: (useExtWorkspace && screen) ? WindowManager.screenProjection(CompositorService.isAqueous ? Quickshell.screens.find(s => s.name === effectiveScreenName) || screen : screen) : null

    readonly property string effectiveScreenName: followFocus ? (BarWidgetService.getFocusedScreenName() || screenName) : screenName
    readonly property bool hiddenByOverview: CompositorService.workspacesHiddenByOverview(effectiveScreenName)
    readonly property string compositorName: CompositorService.compositor

    readonly property var currentWorkspace: {
        if (useExtWorkspace)
            return extProjection?.windowsets.find(ws => ws.active) ?? null;
        if (!useNativeWorkspaces)
            return 1;
        return CompositorService.currentWorkspaceKey(screenName, followFocus);
    }

    readonly property var workspaceList: {
        if (useExtWorkspace) {
            const baseList = extWorkspaces();
            return showPadding ? padWorkspaces(baseList) : baseList;
        }
        if (!useNativeWorkspaces)
            return [1];
        if (hiddenByOverview)
            return [];

        const baseList = CompositorService.workspacesForScreen(screenName, followFocus, {
            "occupiedOnly": occupiedOnly,
            "showAllTags": showAllTags,
            "minCount": showPadding ? paddingCount : 0,
            "showSpecial": showSpecial
        });
        const slots = slotList(baseList);
        if (CompositorService.ephemeralWorkspaces || !showPadding || CompositorService.supportsPersistentWorkspaces || (useAqueous && baseList.length === 0))
            return slots;
        return padWorkspaces(slots);
    }

    readonly property var realWorkspaces: workspaceList.map(ws => recordOf(ws)).filter(ws => ws && !ws.placeholder)
    readonly property bool hasWorkspaces: realWorkspaces.length > 0
    readonly property bool available: useNativeWorkspaces || (useExtWorkspace && hasWorkspaces)

    onCompositorNameChanged: {
        _placeholderPool = [];
        _slotPool = {};
    }

    // Hyprland creates/destroys workspaces on empty enter/leave; slots keyed by id keep delegate identity so pills animate instead of popping
    property var _slotPool: ({})
    readonly property Component _slotComponent: Component {
        QtObject {
            property var ws: null
        }
    }

    function recordOf(entry) {
        if (!entry || entry.ws === undefined)
            return entry;
        return entry.ws;
    }

    function slotList(raw) {
        const live = {};
        const slots = raw.map(ws => {
            const key = ws.id !== null && ws.id !== undefined && !ws.special ? ws.id : (ws.special ? "special:" : "name:") + (ws.name ?? "");
            let entry = _slotPool[key];
            if (!entry) {
                entry = {
                    "slot": _slotComponent.createObject(root),
                    "ws": null
                };
                _slotPool[key] = entry;
            }
            // Compare against the cached record: reading slot.ws here would make workspaceList depend on the write below (binding loop)
            if (entry.ws !== ws) {
                entry.ws = ws;
                entry.slot.ws = ws;
            }
            live[key] = true;
            return entry.slot;
        });
        for (const key in _slotPool) {
            if (live[key])
                continue;
            _slotPool[key].slot.destroy();
            delete _slotPool[key];
        }
        return slots;
    }

    // Stable placeholder instances so ScriptModel reuses padding delegates instead of recreating them on workspace churn
    property var _placeholderPool: []

    function padWorkspaces(list) {
        const padded = list.slice();
        let slot = 0;
        while (padded.length < paddingCount) {
            if (_placeholderPool.length <= slot)
                _placeholderPool.push(WorkspaceModel.placeholder());
            padded.push(_placeholderPool[slot]);
            slot++;
        }
        return padded;
    }

    function extWorkspaces() {
        const fallback = [
            {
                "id": "1",
                "name": "1",
                "active": false
            }
        ];
        if (!extProjection)
            return fallback;

        let visible = extProjection.windowsets.filter(ws => ws.shouldDisplay);
        if (visible.some(ws => ws.coordinates && ws.coordinates.length > 0)) {
            visible = visible.slice().sort((a, b) => {
                const coordsA = a.coordinates || [0, 0];
                const coordsB = b.coordinates || [0, 0];
                if (coordsA[0] !== coordsB[0])
                    return coordsA[0] - coordsB[0];
                return coordsA[1] - coordsB[1];
            });
        }
        return visible.length > 0 ? visible : fallback;
    }

    function isActive(entry) {
        if (useExtWorkspace || !useNativeWorkspaces)
            return entry === currentWorkspace;
        return CompositorService.isCurrentWorkspace(recordOf(entry), currentWorkspace);
    }

    function isOccupied(entry) {
        return useNativeWorkspaces && CompositorService.workspaceOccupied(recordOf(entry));
    }

    function isPlaceholder(entry) {
        return !!(recordOf(entry)?.placeholder);
    }

    function switchTo(entry) {
        const data = recordOf(entry);
        if (!data || data.placeholder)
            return;
        if (useNativeWorkspaces) {
            CompositorService.switchToWorkspace(data, effectiveScreenName);
            return;
        }
        if (useExtWorkspace && typeof data.activate === "function")
            data.activate();
    }

    function step(direction) {
        if (useAqueous) {
            const index = realWorkspaces.findIndex(w => w.id === currentWorkspace);
            const next = Math.max(0, Math.min(realWorkspaces.length - 1, index + (direction > 0 ? 1 : -1)));
            if (next !== index)
                CompositorService.switchToWorkspace(realWorkspaces[next]);
            return;
        }
        if (useExtWorkspace) {
            if (realWorkspaces.length < 2)
                return;
            const currentIndex = realWorkspaces.findIndex(ws => ws === currentWorkspace);
            const validIndex = currentIndex === -1 ? 0 : currentIndex;
            const nextIndex = direction > 0 ? Math.min(validIndex + 1, realWorkspaces.length - 1) : Math.max(validIndex - 1, 0);
            if (nextIndex === validIndex)
                return;
            const nextWorkspace = realWorkspaces[nextIndex];
            if (typeof nextWorkspace.activate === "function")
                nextWorkspace.activate();
            return;
        }
        if (!useNativeWorkspaces)
            return;
        // specials are overlays you toggle, not positions you scroll to
        CompositorService.stepWorkspace(realWorkspaces.map(ws => recordOf(ws)).filter(ws => ws.special !== true), currentWorkspace, direction);
    }

    function secondaryAction(entry) {
        CompositorService.workspaceSecondaryAction(entry ? recordOf(entry) : null, effectiveScreenName);
    }

    property real _touchpadAccumulator: 0
    property real _mouseAccumulator: 0
    property bool _scrollInProgress: false
    readonly property Timer _scrollCooldown: Timer {
        interval: 100
        onTriggered: root._scrollInProgress = false
    }

    function handleWheel(wheel) {
        if (_scrollInProgress)
            return;
        const delta = wheel.angleDelta.y;
        const isTouchpad = WheelInput.isTouchpad(wheel);
        const reverse = reverseScrolling ? -1 : 1;

        if (isTouchpad) {
            _touchpadAccumulator += delta;
            if (Math.abs(_touchpadAccumulator) < 500)
                return;
            step(_touchpadAccumulator * reverse < 0 ? 1 : -1);
            _scrollInProgress = true;
            _scrollCooldown.restart();
            _touchpadAccumulator = 0;
            return;
        }

        _mouseAccumulator += delta;
        if (Math.abs(_mouseAccumulator) < 120)
            return;
        step(_mouseAccumulator * reverse < 0 ? 1 : -1);
        _scrollInProgress = true;
        _scrollCooldown.restart();
        _mouseAccumulator = 0;
    }
}
