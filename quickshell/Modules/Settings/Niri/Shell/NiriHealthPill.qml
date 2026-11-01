import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Widgets
import "../../../../Common/niri/health.js" as Health
import "../../../../DCommon/Common/Contrast.js" as Contrast

Rectangle {
    id: root

    property var report: null
    property bool checking: false
    property string error: ""

    readonly property var findings: report?.findings ?? []
    readonly property int errors: findings.filter(f => f.severity === "error").length
    readonly property int warnings: findings.length - errors
    // The store rolls a failed reload back and marks that version failed
    readonly property bool reloadFailed: NiriPageService.history[0]?.failed ?? false
    readonly property color tone: reloadFailed || errors ? Theme.error : warnings ? Theme.warning : Theme.success
    readonly property Popup popover: popoverLoader.item as Popup
    readonly property color fill: popover?.opened ? Theme.blend(Theme.surfaceContainerHigh, tone, 0.2) : Theme.surfaceContainerHigh
    readonly property string iconName: checking ? "sync" : reloadFailed ? "settings_backup_restore" : errors ? "error" : warnings ? "warning" : "check_circle"
    readonly property string label: {
        if (checking)
            return I18n.tr("Checking", "niri health pill while the doctor runs");
        if (reloadFailed)
            return I18n.tr("Reload failed", "niri health pill, niri refused the last config");
        if (errors)
            return I18n.tr("%1 errors", "niri health pill, count of config errors").arg(errors);
        if (warnings)
            return I18n.tr("%1 to check", "niri health pill, count of config warnings").arg(warnings);
        return I18n.tr("Healthy", "niri health pill, no config problem");
    }

    // shortcut: rules are judged against installed apps and open windows; an app installed elsewhere (flatpak not exported) reads as unknown.
    function appIds() {
        const ids = new Set();
        for (const app of DesktopEntries.applications.values) {
            ids.add(app.id);
            if (app.startupClass)
                ids.add(app.startupClass);
        }
        for (const w of NiriService.windows) {
            if (w.app_id)
                ids.add(w.app_id);
        }
        return [...ids];
    }

    // Status colours are fixed hues that wash out on light surfaces: shift them toward the text colour until they read.
    function legible(tone, background) {
        return Contrast.readableOn(background, [0, 0.25, 0.5, 0.75, 1].map(amount => Contrast.mix(tone, Theme.surfaceText, amount)));
    }

    function check(extra) {
        root.checking = true;
        NiriPageService.request("niri.config.doctor", Object.assign({
            "appIds": appIds()
        }, extra), response => {
            root.checking = false;
            root.error = response.error ?? "";
            if (!response.error)
                root.report = response.result;
            // The doctor only reports: a fragment DMS wrote but niri never includes stays dormant,
            // so the page poses the include itself, through the doctor's own path
            if (!extra?.fix)
                autoInclude();
        });
    }

    // One include at a time: each pose owns the one backup the Undo takes back.
    function autoInclude() {
        const dormant = Health.dormant(root.findings);
        const host = toastHost();
        if (!dormant || !host)
            return;
        root.checking = true;
        NiriPageService.request("niri.config.doctor", {
            "fix": dormant.fix,
            "fragment": Health.fragmentOf(dormant.subject),
            "appIds": appIds()
        }, response => {
            root.checking = false;
            root.error = response.error ?? "";
            if (response.error)
                return;
            root.report = response.result;
            host.announce(Health.fragmentOf(dormant.subject), root);
        });
    }

    // The page's toast banner: found through the parents, like the section keepers find the Keep banner.
    // The parent chain is walked through a var parameter: the host property exists on no static type.
    function toastHostOf(item) {
        if (item && "includeToastHost" in item && item.includeToastHost)
            return item.includeToastHost;
        return null;
    }

    function toastHost() {
        for (let item = root.parent; item; item = item.parent) {
            const host = toastHostOf(item);
            if (host)
                return host;
        }
        return null;
    }

    function fix(finding) {
        check({
            "fix": finding.fix,
            "fragment": finding.subject.replace(/^dms\//, "")
        });
    }

    function undoFix() {
        check({
            "fix": "undo-include"
        });
    }

    function showPopover(toggle) {
        if (!popoverLoader.active) {
            popoverLoader.setSource(Qt.resolvedUrl("NiriHealthPopover.qml"), {
                "health": root
            });
            popoverLoader.active = true;
        }
        if (toggle && popover.opened)
            popover.close();
        else
            popover.open();
    }

    function refresh() {
        check({});
        NiriPageService.refreshHistory();
    }

    width: row.implicitWidth + Theme.spacingM * 2
    height: Theme.iconButtonSize
    radius: Theme.fullRadius(width, height)
    color: fill
    border.width: hover.hovered ? Theme.outlineWidth : 0
    border.color: Theme.outline
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("Health: %1", "niri health pill accessible name").arg(label)
    activeFocusOnTab: true
    Keys.onSpacePressed: showPopover(false)
    Keys.onReturnPressed: showPopover(false)
    Component.onCompleted: refresh()

    Connections {
        target: NiriPageService

        function onApplied() {
            root.refresh();
        }

        function onRefused() {
            root.refresh();
        }
    }

    // dms/input.kdl and dms/cursor.kdl regenerate outside the page's applies:
    // a setting written into a dormant fragment must not stay dormant.
    Timer {
        id: inputCheckTimer
        interval: 800
        onTriggered: root.refresh()
    }

    Connections {
        target: SettingsData

        function onCompositorInputRefreshNeeded() {
            inputCheckTimer.restart();
        }

        function onCompositorCursorRefreshNeeded() {
            inputCheckTimer.restart();
        }
    }

    // The margin brings the hit area to 48 px around the 40 px pill.
    HoverHandler {
        id: hover
        margin: Theme.spacingXS
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        margin: Theme.spacingXS
        onTapped: root.showPopover(true)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: Theme.iconSizeMedium
            color: root.legible(root.tone, root.fill)
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
        }
    }

    FocusRing {}

    // A source URL, not the type: the popover and its rows are not even compiled before the first open
    Loader {
        id: popoverLoader
        anchors.fill: parent
        active: false
    }
}
