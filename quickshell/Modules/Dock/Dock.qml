pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

Variants {
    id: dockVariants
    readonly property var dockSlots: {
        SettingsData.dockConfigs;
        SettingsData.barConfigs;
        const slots = [];
        for (const screen of ShellLayout.realScreens) {
            for (const config of SettingsData.dockConfigsForScreen(screen)) {
                if (CompositorService.frameHostsDockForConfig(screen, config))
                    continue;
                slots.push(JSON.stringify([screen.name, config.id]));
            }
        }
        return slots;
    }

    model: dockVariants.dockSlots

    property var contextMenu
    property var trashContextMenu

    delegate: PanelWindow {
        id: dock
        readonly property alias body: body

        required property var modelData
        readonly property var identity: JSON.parse(modelData)
        readonly property var targetScreen: ShellLayout.screenForName(identity[0])
        readonly property var resolvedConfig: SettingsData.getDockConfig(identity[1])
        // Keep the last resolved config so the body never sees a shapeless one while the delegate is torn down.
        property var config: resolvedConfig
        onResolvedConfigChanged: if (resolvedConfig)
            config = resolvedConfig

        screen: dock.targetScreen
        color: "transparent"

        WlrLayershell.namespace: "dms:dock"
        WlrLayershell.layer: body.editMode || body.usesOverlayLayer ? WlrLayer.Overlay : WlrLayer.Top

        // Edit mode grows the window over the whole screen so the scrim captures every click.
        anchors {
            top: body.editMode || (!body.isVertical ? (dock.config.position === SettingsData.Position.Top) : true)
            bottom: body.editMode || (!body.isVertical ? (dock.config.position === SettingsData.Position.Bottom) : true)
            left: body.editMode || (!body.isVertical ? true : (dock.config.position === SettingsData.Position.Left))
            right: body.editMode || (!body.isVertical ? true : (dock.config.position === SettingsData.Position.Right))
        }

        visible: !!resolvedConfig && (resolvedConfig.enabled || (resolvedConfig.openOnOverview && CompositorService.isNiri))
        WlrLayershell.keyboardFocus: PopoutManager.screenshotActive ? WlrKeyboardFocus.None : body.editMode ? WlrKeyboardFocus.Exclusive : body.interactionActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        implicitWidth: body.surfaceImplicitWidth
        implicitHeight: body.surfaceImplicitHeight
        readonly property bool manualPlacement: body.editMode || (body.isVertical && dock.config.mode === "taskbar")
        exclusiveZone: manualPlacement ? -1 : body.surfaceExclusiveZone

        Component.onCompleted: SurfaceRecovery.track(dock)
        Component.onDestruction: SurfaceRecovery.untrack(dock)

        WindowBlur {
            targetWindow: dock
            blurEnabled: !body.usesConnectedFrameChrome
            surfaceColor: body.surfaceColor
            blurX: body.blurX
            blurY: body.blurY
            blurWidth: body.blurWidth
            blurHeight: body.blurHeight
            blurRadius: body.blurRadius
        }

        mask: body.editMode ? null : bodyMask

        Region {
            id: bodyMask
            item: body.inputMaskItem
        }

        DockBody {
            id: body
            anchors.fill: parent
            config: dock.config
            hostWindow: dock
            modelData: dock.targetScreen
            contextMenu: dockVariants.contextMenu
            trashContextMenu: dockVariants.trashContextMenu
        }

        EdgeExclusion {
            screen: dock.targetScreen
            edge: body.connectedBarSide
            exclusionSize: (dock.manualPlacement || body.frameDockExclusionActive) && body.shouldReserveDockSpace ? body.dockReserveZone : 0
            layerNamespace: "dms:dock-exclusion"
        }
    }
}
