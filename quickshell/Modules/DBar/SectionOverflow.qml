pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.SurfaceWidgets
import qs.DCommon.Widgets
import qs.Widgets
import "OverflowLayout.js" as OverflowLayout

Item {
    id: root

    required property var sectionContext
    readonly property alias button: button
    property bool wantOpen: false
    readonly property var popout: popupLoader.item
    readonly property bool open: popout?.shouldBeVisible ?? false
    readonly property var popupParent: popout?.contentLoader.item?.widgetHost ?? null
    readonly property var entries: sectionContext.hiddenEntries
    readonly property real naturalWidth: entries.reduce((width, entry) => Math.max(width, entry.itemWidth), 0)
    readonly property real naturalHeight: entries.reduce((height, entry) => height + entry.itemHeight, 0) + Math.max(0, entries.length - 1) * Theme.spacingS
    readonly property real popupWidth: Math.min(naturalWidth + Theme.spacingS * 2, (sectionContext.parentScreen?.width ?? Infinity) - Theme.spacingL * 2)
    readonly property real popupHeight: Math.min(naturalHeight + Theme.spacingS * 2, (sectionContext.parentScreen?.height ?? Infinity) - Theme.spacingL * 2)
    readonly property real contentWidth: Math.max(naturalWidth, popupWidth - Theme.spacingS * 2)

    onWantOpenChanged: sectionContext.overflowWanted = wantOpen
    Component.onDestruction: sectionContext.overflowWanted = false
    onEntriesChanged: positionEntries()
    onNaturalHeightChanged: positionEntries()
    onContentWidthChanged: positionEntries()

    function positionEntries() {
        let y = 0;
        for (const entry of entries) {
            entry.popupX = (contentWidth - entry.itemWidth) / 2;
            entry.popupY = y;
            y += entry.itemHeight + Theme.spacingS;
        }
    }

    function toggle() {
        if (open) {
            popout.close();
            return;
        }
        if (popout)
            showPopout();
        else
            wantOpen = true;
    }

    function showPopout() {
        if (!sectionContext.surfaceContext?.positionPopout(popout, button, sectionContext.section)) {
            wantOpen = false;
            return;
        }
        positionEntries();
        PopoutManager.requestPopout(popout, undefined, "bar-overflow-" + (sectionContext.barConfig?.id ?? "") + "-" + sectionContext.section);
    }

    BarPill {
        id: button
        parent: root.sectionContext
        axis: root.sectionContext.axis
        section: root.sectionContext.section
        parentScreen: root.sectionContext.parentScreen
        widgetThickness: root.sectionContext.widgetThickness
        barThickness: root.sectionContext.barThickness
        barSpacing: root.sectionContext.barSpacing
        barConfig: root.sectionContext.barConfig
        widgetBackground: root.sectionContext.overflowBackground
        sectionSpacing: root.sectionContext.widgetSpacing
        segmentRole: root.sectionContext.overflowSegmentRole
        isFirst: root.sectionContext.inlineOrder[0] === -1
        isLast: root.sectionContext.inlineOrder[root.sectionContext.inlineOrder.length - 1] === -1
        isLeftBarEdge: !root.sectionContext.isVertical && section === "left" && root.sectionContext.edgeIsScreenEdge
        isRightBarEdge: !root.sectionContext.isVertical && section === "right" && root.sectionContext.edgeIsScreenEdge
        isTopBarEdge: root.sectionContext.isVertical && section === "left" && root.sectionContext.edgeIsScreenEdge
        isBottomBarEdge: root.sectionContext.isVertical && section === "right" && root.sectionContext.edgeIsScreenEdge
        crossEdgeExtension: !root.sectionContext.isVertical && section !== "center" ? root.sectionContext.crossEdgeExtension : 0
        blurBarWindow: root.sectionContext.blurBarWindow
        x: root.sectionContext.isVertical ? (root.sectionContext.width - width) / 2 : root.sectionContext.overflowButtonPosition
        y: root.sectionContext.isVertical ? root.sectionContext.overflowButtonPosition : (root.sectionContext.height - height) / 2
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("More widgets", "accessible name of the bar overflow button")
        Accessible.description: I18n.tr("Overflow") + ": " + root.sectionContext.overflowCount
        onClicked: root.toggle()
        Keys.onSpacePressed: event => {
            root.toggle();
            event.accepted = true;
        }
        Keys.onReturnPressed: event => {
            root.toggle();
            event.accepted = true;
        }
        content: Component {
            Item {
                implicitWidth: Math.max(0, root.button.widgetThickness - root.button.horizontalPadding * 2)
                implicitHeight: implicitWidth
                DIcon {
                    anchors.centerIn: parent
                    name: OverflowLayout.expanderIcon(root.sectionContext.axis?.edge, root.open)
                    size: Theme.iconSizeSmall
                    color: Theme.widgetTextColor
                }
            }
        }
    }

    Loader {
        id: popupLoader
        active: root.wantOpen
        onLoaded: root.showPopout()
        sourceComponent: Component {
            DPopout {
                layerNamespace: "dms:bar-overflow"
                screen: root.sectionContext.parentScreen
                popupWidth: root.popupWidth
                popupHeight: root.popupHeight
                onBackgroundClicked: close()
                onCloseAnimationFinished: root.wantOpen = false
                content: Component {
                    Item {
                        readonly property var widgetHost: scroller.contentItem
                        // A hosted widget holding focus would starve the popout's own Escape handler.
                        Keys.onEscapePressed: root.popout?.close()
                        DFlickable {
                            id: scroller
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            contentWidth: root.contentWidth
                            contentHeight: root.naturalHeight
                            flickableDirection: Flickable.AutoFlickIfNeeded
                            clip: true
                        }
                    }
                }
            }
        }
    }
}
