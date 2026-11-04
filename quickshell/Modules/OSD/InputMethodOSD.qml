import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    osdKind: "inputMethod"

    property string lastIM: ""
    property bool imInitialized: false
    readonly property string currentIM: Fcitx5Service.currentIMLabel
    readonly property string imLabel: currentIM
    readonly property real horizontalPadding: Theme.spacingL
    readonly property real itemSpacing: Theme.spacingM
    readonly property real labelWidth: Math.ceil(labelMetrics.width)

    osdWidth: Math.min(screenWidth - Theme.spacingM * 2, Math.max(180, horizontalPadding * 2 + Theme.buttonHeightS + itemSpacing + labelWidth + Theme.spacingM * 2))
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    function observeIM() {
        if (currentIM === "") {
            imInitialized = false;
            lastIM = "";
            return;
        }
        if (!imInitialized) {
            lastIM = currentIM;
            imInitialized = true;
            return;
        }
        if (lastIM === currentIM)
            return;
        lastIM = currentIM;
        if (SettingsData.osdInputMethodEnabled)
            show();
    }

    onCurrentIMChanged: observeIM()

    Component.onCompleted: {
        Fcitx5Service.consumers++;
        observeIM();
    }
    Component.onDestruction: Fcitx5Service.consumers--

    StyledTextMetrics {
        id: labelMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: root.imLabel
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
                iconName: "language"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.imLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
