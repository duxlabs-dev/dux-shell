pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash.Overview
import qs.Modules.Settings.DesktopWidgetSettings
import qs.Modules.Settings.Widgets
import "../../DCommon/Common/FocusNavigation.js" as FocusNavigation

FocusScope {
    id: root

    required property WidgetEditLayer editLayer
    readonly property bool lockScreen: editLayer.lockScreen
    readonly property bool greeter: editLayer.greeter
    property bool libraryOpen: false
    readonly property real fabReserved: fabBar.reservedHeight
    readonly property var singletonTypes: ["lockAuth", "greeterSession"]
    readonly property var libraryWidgets: DesktopWidgetRegistry.getListWidgets(editLayer.listKey).filter(widget => {
        if (!lockScreen)
            return true;
        return !singletonTypes.includes(widget.id) || !SettingsData.widgetInstanceOfType(editLayer.listKey, widget.id);
    }).map(widget => ({
                id: widget.id,
                text: widget.name,
                icon: widget.icon,
                description: widget.description
            }))

    readonly property string surfaceLabel: {
        if (greeter)
            return SettingsData.greeterFollowLockScreen ? I18n.tr("Editing the login screen, shared with the lock screen", "widget editor banner") : I18n.tr("Editing the login screen", "widget editor banner");
        if (!lockScreen || !GreeterService.available)
            return "";
        return SettingsData.greeterFollowLockScreen && GreeterService.slotState !== "" ? I18n.tr("Editing the lock screen, the login screen follows it", "widget editor banner") : I18n.tr("Editing the lock screen", "widget editor banner");
    }

    property string optionsInstanceId: ""
    readonly property string selectedInstanceId: editLayer.selectedInstanceId
    readonly property Item optionsTarget: optionsInstanceId !== "" && optionsInstanceId === selectedInstanceId ? editLayer.itemById(optionsInstanceId) : null

    signal finished

    onSelectedInstanceIdChanged: {
        if (selectedInstanceId !== optionsInstanceId)
            optionsInstanceId = "";
    }

    function closeLibrary() {
        libraryOpen = false;
        forceActiveFocus();
    }

    function showOptions(instanceId) {
        if (optionsInstanceId === instanceId) {
            closeOptions();
            return;
        }
        optionsInstanceId = instanceId;
        editLayer.selectedInstanceId = instanceId;
    }

    function closeOptions() {
        const target = optionsTarget;
        optionsInstanceId = "";
        target?.forceActiveFocus();
    }

    function addWidget(widgetType) {
        const def = DesktopWidgetRegistry.getWidget(widgetType);
        const instance = SettingsData.createDesktopWidgetInstance(widgetType, def?.name ?? widgetType, DesktopWidgetRegistry.getDefaultConfig(widgetType), editLayer.listKey);
        editLayer.pendingIds = editLayer.pendingIds.concat([instance.id]);
    }

    function resetLayout() {
        if (greeter) {
            SettingsData.resetGreeterWidgets();
            return;
        }
        if (lockScreen) {
            SettingsData.resetLockScreenWidgets();
            return;
        }
        for (const instance of SettingsData.desktopWidgetInstances || [])
            SessionData.resetDesktopWidgetInstanceGeometry(instance.id, ["x", "y", "width", "height"]);
    }

    function dismiss() {
        if (optionsTarget) {
            closeOptions();
            return;
        }
        if (editControls.pendingAction !== "") {
            editControls.cancelConfirmation();
            return;
        }
        if (libraryOpen) {
            closeLibrary();
            return;
        }
        finished();
    }

    focus: true
    Component.onCompleted: {
        libraryOpen = DesktopWidgetRegistry.libraryScreen === editLayer.screenName;
        forceActiveFocus();
        if (!lockScreen && DesktopWidgetRegistry.optionsScreen === editLayer.screenName)
            showOptions(DesktopWidgetRegistry.optionsInstanceId);
    }
    Keys.onEscapePressed: event => {
        if (PopoutManager.screenshotActive) {
            event.accepted = false;
            return;
        }
        dismiss();
    }

    MouseArea {
        anchors.fill: parent
        visible: root.libraryOpen
        acceptedButtons: Qt.AllButtons
        onClicked: root.closeLibrary()
    }

    Loader {
        anchors.centerIn: parent
        active: root.libraryOpen

        sourceComponent: CcWidgetLibrary {
            width: Math.min(implicitWidth, root.width - Theme.spacingL * 2)
            height: Math.min(implicitHeight, root.height - Theme.spacingL * 2)
            widgets: root.libraryWidgets
            Component.onCompleted: reset()
            onChosen: widgetId => {
                root.addWidget(widgetId);
                root.closeLibrary();
            }
            onDismissed: root.closeLibrary()
        }
    }

    Rectangle {
        visible: root.surfaceLabel !== "" && fabBar.shown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: fabBar.reservedHeight + Theme.spacingL + (gridHint.visible ? gridHint.height + Theme.spacingS : 0)
        width: surfaceRow.implicitWidth + Theme.spacingL * 2
        height: Theme.buttonHeightM
        radius: Theme.fullRadius(width, height)
        color: Theme.readableSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        Row {
            id: surfaceRow
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.greeter ? "login" : "lock"
                size: Theme.iconSizeMedium
                color: Theme.primary
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.surfaceLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }
    }

    DesktopWidgetGridHint {
        id: gridHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: fabBar.reservedHeight + Theme.spacingL
        visible: fabBar.shown && (root.editLayer.selectedInstanceId !== "" || root.editLayer.interactingItem !== null)
        gridEnabled: root.editLayer.gridEnabled
        gridSize: root.editLayer.gridSize
    }

    SettingsFabBar {
        id: fabBar
        shown: !root.libraryOpen

        DashEditControls {
            id: editControls
            canClear: false
            onAddRequested: {
                root.optionsInstanceId = "";
                root.libraryOpen = true;
            }
            onResetRequested: root.resetLayout()
            onFinished: root.finished()
        }
    }

    Loader {
        active: root.optionsTarget !== null

        sourceComponent: FocusScope {
            id: panel

            readonly property Item target: root.optionsTarget
            readonly property var instanceData: SettingsData.getDesktopWidgetInstance(root.optionsInstanceId)
            readonly property var widgetDef: DesktopWidgetRegistry.getWidget(instanceData?.widgetType ?? "")
            readonly property real margin: Theme.spacingL
            readonly property real padding: PopoutMetrics.contentPadding
            readonly property real focusPadding: SettingsMetrics.focusGutter
            readonly property real bottomLimit: root.height - root.fabReserved - margin
            readonly property real gap: (target?.chromeOutset ?? 0) + Theme.spacingS
            readonly property real afterEdge: (target?.x ?? 0) + (target?.width ?? 0) + gap
            readonly property real beforeEdge: (target?.x ?? 0) - gap
            readonly property real afterRoom: root.width - margin - afterEdge
            readonly property real beforeRoom: beforeEdge - margin
            readonly property real maxWidth: Math.min(Theme.dialogMaxWidth, root.width - margin * 2)
            readonly property real minWidth: Math.min(SettingsMetrics.windowMinWidth, maxWidth)
            readonly property real firstRoom: I18n.isRtl ? beforeRoom : afterRoom
            readonly property real secondRoom: I18n.isRtl ? afterRoom : beforeRoom
            readonly property bool onAfter: (firstRoom >= minWidth || firstRoom >= secondRoom) !== I18n.isRtl
            readonly property Item windowFocusItem: Window.activeFocusItem

            x: Math.max(margin, Math.min(root.width - margin - width, onAfter ? afterEdge : beforeEdge - width))
            y: Math.max(margin, Math.min(bottomLimit - height, target?.y ?? 0))
            width: Math.min(maxWidth, Math.max(minWidth, onAfter ? afterRoom : beforeRoom))
            height: Math.min(bottomLimit - margin, header.height + PopoutMetrics.contentGap + settings.implicitHeight + padding * 2)
            focus: true
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            Accessible.role: Accessible.Dialog
            Accessible.name: header.title
            Component.onCompleted: forceActiveFocus()

            onWindowFocusItemChanged: {
                const item = windowFocusItem;
                if (!item || !FocusNavigation.containsFocus(settings))
                    return;
                const top = item.mapToItem(scroll.contentItem, 0, 0).y;
                scroll.revealRange(top - focusPadding, top + item.height + focusPadding);
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.windowRadius
                color: Theme.cardSurface
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineMedium

                ElevationShadow {
                    anchors.fill: parent
                    z: -1
                    level: Theme.elevationLevel2
                    targetRadius: parent.radius
                    targetColor: "transparent"
                    shadowEnabled: Theme.elevationEnabled
                }

                // Presses and hover that miss a control would reach the widgets and the deselect area below.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    hoverEnabled: true
                    cursorShape: Qt.ArrowCursor
                }
            }

            DWindowHeader {
                id: header
                x: panel.padding
                y: panel.padding
                width: parent.width - panel.padding * 2
                controls: null
                horizontalPadding: 0
                verticalPadding: 0
                title: panel.instanceData?.name || panel.widgetDef?.name || ""
                onCloseRequested: root.closeOptions()
            }

            DFlickable {
                id: scroll
                x: panel.padding - panel.focusPadding
                y: header.y + header.height + PopoutMetrics.contentGap - panel.focusPadding
                width: parent.width - x * 2
                height: Math.max(0, parent.height - y - panel.padding + panel.focusPadding)
                contentWidth: width
                contentHeight: settings.implicitHeight + panel.focusPadding * 2
                clip: true

                DesktopWidgetTypeSettings {
                    id: settings
                    x: panel.focusPadding
                    y: panel.focusPadding
                    width: scroll.width - panel.focusPadding * 2
                    instanceId: root.optionsInstanceId
                    instanceData: panel.instanceData
                    widgetDef: panel.widgetDef
                }
            }
        }
    }
}
