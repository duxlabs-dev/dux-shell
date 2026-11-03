import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    osdKind: "keyboardLayout"

    property string lastLayout: ""
    property bool layoutInitialized: false
    readonly property string currentLayout: KeyboardLayoutService.currentLayout
    readonly property string layoutLabel: currentLayout
    readonly property real horizontalPadding: Theme.spacingL
    readonly property real itemSpacing: Theme.spacingM
    readonly property real labelWidth: Math.ceil(labelMetrics.width)

    osdWidth: Math.min(screenWidth - Theme.spacingM * 2, Math.max(180, horizontalPadding * 2 + Theme.buttonHeightS + itemSpacing + labelWidth + Theme.spacingM * 2))
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    function observeLayout() {
        if (!KeyboardLayoutService.layoutKnown) {
            layoutInitialized = false;
            lastLayout = "";
            return;
        }
        if (!layoutInitialized) {
            lastLayout = currentLayout;
            layoutInitialized = true;
            return;
        }
        if (lastLayout === currentLayout)
            return;
        lastLayout = currentLayout;
        if (SettingsData.osdKeyboardLayoutEnabled)
            show();
    }

    onCurrentLayoutChanged: observeLayout()

    Component.onCompleted: {
        KeyboardLayoutService.consumers++;
        observeLayout();
    }
    Component.onDestruction: KeyboardLayoutService.consumers--

    StyledTextMetrics {
        id: labelMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: root.layoutLabel
    }

    content: Item {
        anchors.fill: parent

        RowLayout {
            anchors {
                fill: parent
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: root.itemSpacing

            OsdIcon {
                Layout.alignment: Qt.AlignVCenter
                iconName: "keyboard"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.layoutLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
