import QtQuick
import qs.Common
import qs.Modules.DBar
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:layout"

    property var triggerScreen: null

    readonly property bool isMango: CompositorService.isMango

    function setTriggerPosition(x, y, width, section, screen, barPosition, barThickness, barSpacing, barConfig) {
        triggerX = x;
        triggerY = y;
        triggerWidth = width;
        triggerSection = section;
        triggerScreen = screen;
        root.screen = screen;

        storedBarThickness = barThickness !== undefined ? barThickness : Theme.barThickness(SettingsData.getPrimaryBarConfig()?.innerPadding ?? SettingsData.barInnerPaddingDefault, 1);
        storedBarSpacing = barSpacing !== undefined ? barSpacing : 4;
        storedBarConfig = barConfig;

        const pos = barPosition !== undefined ? barPosition : 0;
        const bottomGap = barConfig ? (barConfig.bottomGap !== undefined ? barConfig.bottomGap : 0) : 0;

        setBarContext(pos, bottomGap);

        updateOutputState();
    }

    onScreenChanged: updateOutputState()

    function updateOutputState() {
        if (screen && MangoService.available) {
            outputState = MangoService.getOutputState(screen.name);
        } else {
            outputState = null;
        }
    }

    property var outputState: null
    property string currentLayoutSymbol: outputState?.layoutSymbol || ""

    readonly property var layoutNames: ({
            "CT": I18n.tr("Center Tiling"),
            "G": I18n.tr("Grid"),
            "K": I18n.tr("Deck", "window tiling layout name in layout picker"),
            "M": I18n.tr("Monocle", "window tiling layout name in layout picker"),
            "RT": I18n.tr("Right Tiling"),
            "S": I18n.tr("Scrolling", "window tiling layout name in layout picker"),
            "T": I18n.tr("Tiling", "window tiling layout name in layout picker"),
            "VG": I18n.tr("Vertical Grid"),
            "VK": I18n.tr("Vertical Deck"),
            "VS": I18n.tr("Vertical Scrolling"),
            "VT": I18n.tr("Vertical Tiling")
        })

    readonly property var layoutIcons: ({
            "CT": "view_compact",
            "G": "grid_view",
            "K": "layers",
            "M": "fullscreen",
            "RT": "view_sidebar",
            "S": "view_carousel",
            "T": "view_quilt",
            "VG": "grid_on",
            "VK": "view_day",
            "VS": "scrollable_header",
            "VT": "clarify"
        })

    function getLayoutName(symbol) {
        return layoutNames[symbol] || symbol;
    }

    function getLayoutIcon(symbol) {
        return layoutIcons[symbol] || "view_quilt";
    }

    Connections {
        target: MangoService
        function onStateChanged() {
            updateOutputState();
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            updateOutputState();
        }
    }

    Component.onCompleted: {
        updateOutputState();
    }

    popupWidth: 300
    popupHeight: contentLoader.item ? contentLoader.item.implicitHeight : 550
    triggerWidth: 70
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false

    onBackgroundClicked: close()

    content: Component {
        Rectangle {
            id: layoutContent

            implicitHeight: contentColumn.implicitHeight + PopoutMetrics.contentPadding * 2
            color: "transparent"
            focus: true

            Component.onCompleted: {
                if (root.shouldBeVisible) {
                    forceActiveFocus();
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }

            readonly property bool rootShouldBeVisible: root.shouldBeVisible

            onRootShouldBeVisibleChanged: {
                if (rootShouldBeVisible) {
                    Qt.callLater(() => {
                        layoutContent.forceActiveFocus();
                    });
                }
            }

            Column {
                id: contentColumn

                width: parent.width - PopoutMetrics.contentPadding * 2
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: PopoutMetrics.contentPadding
                spacing: PopoutMetrics.contentGap

                StyledText {
                    text: I18n.tr("Available Layouts")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextMedium
                    font.weight: Theme.fontWeightMedium
                }

                Column {
                    id: layoutList
                    width: parent.width
                    spacing: Theme.groupedListGap

                    Repeater {
                        id: layoutRepeater
                        model: MangoService.layouts

                        delegate: DListItem {
                            id: layoutRow
                            required property string modelData
                            required property int index

                            readonly property bool isActive: modelData === root.currentLayoutSymbol

                            width: layoutList.width
                            implicitHeight: BarMetrics.popoutRowTwoLineHeight
                            firstInGroup: index === 0
                            lastInGroup: index === layoutRepeater.count - 1
                            isSelected: isActive
                            Accessible.name: root.getLayoutName(modelData)
                            onClicked: {
                                if (!root.triggerScreen || !MangoService.available)
                                    return;
                                MangoService.setLayout(root.triggerScreen.name, index);
                                root.close();
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingL
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingM

                                DIcon {
                                    name: root.getLayoutIcon(layoutRow.modelData)
                                    size: Theme.iconSizeMedium
                                    color: layoutRow.contentColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXXS

                                    StyledText {
                                        text: root.getLayoutName(layoutRow.modelData)
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: layoutRow.contentColor
                                        font.weight: layoutRow.isActive ? Theme.fontWeightMedium : Theme.fontWeight
                                    }

                                    StyledText {
                                        text: layoutRow.modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: layoutRow.supportingContentColor
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    text: I18n.tr("Right-click bar widget to cycle")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.outline
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
