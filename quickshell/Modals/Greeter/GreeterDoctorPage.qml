import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root
    readonly property var log: Log.scoped("GreeterDoctorPage")

    property bool isRunning: false
    property bool hasRun: false
    property var doctorResults: null
    property int errorCount: 0
    property int warningCount: 0
    property int okCount: 0
    property int infoCount: 0
    property string selectedFilter: "error"

    readonly property real loadingContainerSize: Math.round(Theme.iconSize * 5)
    readonly property real pulseRingSize: Math.round(Theme.iconSize * 3.3)
    readonly property real centerIconContainerSize: Math.round(Theme.iconSize * 2.67)
    readonly property real headerIconContainerSize: Math.round(Theme.iconSize * 2)

    readonly property var filteredResults: {
        if (!doctorResults?.results)
            return [];
        return doctorResults.results.filter(r => r.status === selectedFilter);
    }

    function runDoctor() {
        hasRun = false;
        isRunning = true;
        doctorProcess.running = true;
    }

    Component.onCompleted: runDoctor()

    Item {
        id: loadingView
        anchors.fill: parent
        visible: root.isRunning

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingXL

            Item {
                width: root.loadingContainerSize
                height: root.loadingContainerSize
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    id: pulseRing1
                    anchors.centerIn: parent
                    width: root.pulseRingSize
                    height: root.pulseRingSize
                    radius: root.pulseRingSize / 2
                    color: "transparent"
                    border.width: Math.round(Theme.spacingXS * 0.75)
                    border.color: Theme.primary
                    opacity: 0

                    OpacityAnimator on opacity {
                        running: root.isRunning
                        loops: Animation.Infinite
                        from: 0.8
                        to: 0
                        duration: 1500
                        easing.type: Easing.OutQuad
                    }

                    ScaleAnimator on scale {
                        running: root.isRunning
                        loops: Animation.Infinite
                        from: 0.5
                        to: 1.5
                        duration: 1500
                        easing.type: Easing.OutQuad
                    }
                }

                Rectangle {
                    id: pulseRing2
                    anchors.centerIn: parent
                    width: root.pulseRingSize
                    height: root.pulseRingSize
                    radius: root.pulseRingSize / 2
                    color: "transparent"
                    border.width: Math.round(Theme.spacingXS * 0.75)
                    border.color: Theme.secondary
                    opacity: 0

                    OpacityAnimator on opacity {
                        running: root.isRunning
                        loops: Animation.Infinite
                        from: 0.8
                        to: 0
                        duration: 1500
                        easing.type: Easing.OutQuad
                    }

                    ScaleAnimator on scale {
                        running: root.isRunning
                        loops: Animation.Infinite
                        from: 0.3
                        to: 1.3
                        duration: 1500
                        easing.type: Easing.OutQuad
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.centerIconContainerSize
                    height: root.centerIconContainerSize
                    radius: root.centerIconContainerSize / 2
                    color: Theme.primaryContainer

                    DIcon {
                        anchors.centerIn: parent
                        name: "vital_signs"
                        size: Theme.iconSizeLarge
                        color: Theme.accentOnPrimaryContainer
                    }

                    SequentialAnimation on scale {
                        running: root.isRunning
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 1
                            to: 1.1
                            duration: 750
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: 1.1
                            to: 1
                            duration: 750
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS

                StyledText {
                    text: I18n.tr("System check", "greeter doctor page title")
                    font.pixelSize: Theme.fontSizeXLarge
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: I18n.tr("Analyzing configuration...", "greeter doctor page loading text")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Item {
        id: resultsView
        anchors.fill: parent
        visible: root.hasRun && !root.isRunning
        opacity: (root.hasRun && !root.isRunning) ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Theme.emphasizedEasing
            }
        }

        Column {
            id: headerSection
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Theme.spacingL
            anchors.leftMargin: Theme.spacingXL
            anchors.rightMargin: Theme.spacingXL
            spacing: Theme.spacingL

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingM

                Rectangle {
                    width: root.headerIconContainerSize
                    height: root.headerIconContainerSize
                    radius: Math.round(root.headerIconContainerSize * 0.29)
                    color: root.errorCount > 0 ? Theme.errorContainer : Theme.primaryContainer
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        anchors.centerIn: parent
                        name: root.errorCount > 0 ? "warning" : "check_circle"
                        size: Theme.iconSize + 4
                        color: root.errorCount > 0 ? Theme.onErrorContainer : Theme.accentOnPrimaryContainer
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS

                    StyledText {
                        text: I18n.tr("System check", "greeter doctor page title")
                        font.pixelSize: Theme.fontSizeXLarge
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: {
                            if (root.errorCount === 0)
                                return I18n.tr("All checks passed", "greeter doctor page success");
                            return root.errorCount === 1 ? I18n.tr("%1 issue found", "greeter doctor page error count").arg(root.errorCount) : I18n.tr("%1 issues found", "greeter doctor page error count").arg(root.errorCount);
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: root.errorCount > 0 ? Theme.error : Theme.surfaceVariantText
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                GreeterStatusCard {
                    width: (parent.width - Theme.spacingS * 3) / 4
                    count: root.errorCount
                    label: I18n.tr("Errors", "greeter doctor page status card")
                    iconName: "error"
                    iconColor: Theme.error
                    bgColor: Theme.errorContainer || Theme.withAlpha(Theme.error, 0.15)
                    selected: root.selectedFilter === "error"
                    onClicked: root.selectedFilter = "error"
                }

                GreeterStatusCard {
                    width: (parent.width - Theme.spacingS * 3) / 4
                    count: root.warningCount
                    label: I18n.tr("Warnings", "greeter doctor page status card")
                    iconName: "warning"
                    iconColor: Theme.warning
                    bgColor: Theme.withAlpha(Theme.warning, 0.15)
                    selected: root.selectedFilter === "warn"
                    onClicked: root.selectedFilter = "warn"
                }

                GreeterStatusCard {
                    width: (parent.width - Theme.spacingS * 3) / 4
                    count: root.infoCount
                    label: I18n.tr("Info", "greeter doctor page status card")
                    iconName: "info"
                    iconColor: Theme.secondary
                    bgColor: Theme.withAlpha(Theme.secondary, 0.15)
                    selected: root.selectedFilter === "info"
                    onClicked: root.selectedFilter = "info"
                }

                GreeterStatusCard {
                    width: (parent.width - Theme.spacingS * 3) / 4
                    count: root.okCount
                    label: I18n.tr("OK", "greeter doctor page status card")
                    iconName: "check_circle"
                    iconColor: Theme.success
                    bgColor: Theme.withAlpha(Theme.success, 0.15)
                    selected: root.selectedFilter === "ok"
                    onClicked: root.selectedFilter = "ok"
                }
            }
        }

        Rectangle {
            id: resultsContainer
            anchors.top: headerSection.bottom
            anchors.bottom: footerSection.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Theme.spacingL
            anchors.bottomMargin: Theme.spacingM
            anchors.leftMargin: Theme.spacingXL
            anchors.rightMargin: Theme.spacingXL
            radius: Theme.cornerRadius
            color: Theme.floatingWindowNestedSurface
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            clip: true

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                visible: root.filteredResults.length === 0

                DIcon {
                    name: {
                        switch (root.selectedFilter) {
                        case "error":
                            return "check_circle";
                        case "warn":
                            return "thumb_up";
                        case "info":
                            return "info";
                        default:
                            return "verified";
                        }
                    }
                    size: Math.round(Theme.iconSize * 1.67)
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: {
                        switch (root.selectedFilter) {
                        case "error":
                            return I18n.tr("No errors", "greeter doctor page empty state");
                        case "warn":
                            return I18n.tr("No warnings", "greeter doctor page empty state");
                        case "info":
                            return I18n.tr("No info items", "greeter doctor page empty state");
                        default:
                            return I18n.tr("No checks passed", "greeter doctor page empty state");
                        }
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            DFlickable {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                clip: true
                contentHeight: resultsColumn.height
                contentWidth: width
                visible: root.filteredResults.length > 0

                Column {
                    id: resultsColumn
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.filteredResults

                        GreeterDoctorResultItem {
                            width: resultsColumn.width
                            resultData: modelData
                        }
                    }
                }
            }
        }

        Row {
            id: footerSection
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Theme.spacingL
            spacing: Theme.spacingM

            DButton {
                text: I18n.tr("Run Again", "greeter doctor page button")
                iconName: "refresh"
                backgroundColor: Theme.chipSurface
                textColor: Theme.surfaceText
                onClicked: root.runDoctor()
            }
        }
    }

    Process {
        id: doctorProcess
        command: ["dms", "doctor", "--json"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.isRunning = false;
                root.hasRun = true;
                try {
                    root.doctorResults = JSON.parse(text);
                    if (root.doctorResults?.summary) {
                        root.errorCount = root.doctorResults.summary.errors || 0;
                        root.warningCount = root.doctorResults.summary.warnings || 0;
                        root.okCount = root.doctorResults.summary.ok || 0;
                        root.infoCount = root.doctorResults.summary.info || 0;
                    }
                    if (root.errorCount > 0)
                        root.selectedFilter = "error";
                    else if (root.warningCount > 0)
                        root.selectedFilter = "warn";
                    else if (root.infoCount > 0)
                        root.selectedFilter = "info";
                    else
                        root.selectedFilter = "ok";
                } catch (e) {
                    log.error("Failed to parse doctor output:", e);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.isRunning = false;
                root.hasRun = true;
            }
        }
    }
}
