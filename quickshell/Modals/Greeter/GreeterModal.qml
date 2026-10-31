import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DFloatingWindow {
    id: root
    readonly property var log: Log.scoped("GreeterModal")

    property int currentPage: 0
    readonly property int totalPages: 4
    readonly property var pageComponents: [welcomePage, doctorPage, pluginsPage, completePage]

    property var cheatsheetData: ({})
    property bool cheatsheetLoaded: false

    readonly property int modalWidth: 720
    readonly property int modalHeight: heightWithin(760, 80)

    signal greeterCompleted

    Component.onCompleted: Qt.callLater(loadCheatsheet)

    function loadCheatsheet() {
        const provider = KeybindsService.cheatsheetProvider;
        if (KeybindsService.cheatsheetAvailable && provider && !cheatsheetLoaded) {
            cheatsheetProcess.command = ["dms", "keybinds", "show", provider];
            cheatsheetProcess.running = true;
        }
    }

    Connections {
        target: KeybindsService
        function onCheatsheetAvailableChanged() {
            if (KeybindsService.cheatsheetAvailable && !root.cheatsheetLoaded)
                loadCheatsheet();
        }
    }

    function getKeybind(actionPattern) {
        if (!cheatsheetLoaded || !cheatsheetData.binds)
            return "";
        for (const category in cheatsheetData.binds) {
            const binds = cheatsheetData.binds[category];
            for (let i = 0; i < binds.length; i++) {
                const bind = binds[i];
                if (bind.action && bind.action.includes(actionPattern))
                    return bind.key || "";
            }
        }
        return "";
    }

    function show() {
        currentPage = FirstLaunchService.requestedStartPage || 0;
        visible = true;
    }

    function showAtPage(page) {
        currentPage = page;
        visible = true;
    }

    function nextPage() {
        if (currentPage < totalPages - 1)
            currentPage++;
    }

    function prevPage() {
        if (currentPage > 0)
            currentPage--;
    }

    function finish() {
        FirstLaunchService.markFirstLaunchComplete();
        greeterCompleted();
        visible = false;
    }

    function skip() {
        FirstLaunchService.markFirstLaunchComplete();
        greeterCompleted();
        visible = false;
    }

    objectName: "greeterModal"
    title: I18n.tr("Welcome", "greeter modal window title")
    implicitWidth: modalWidth
    implicitHeight: modalHeight
    minimumSize: Qt.size(modalWidth, modalHeight)
    maximumSize: Qt.size(modalWidth, modalHeight)
    visible: false

    onClosed: visible = false

    Process {
        id: cheatsheetProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const trimmed = text.trim();
                if (trimmed.length === 0)
                    return;
                try {
                    root.cheatsheetData = JSON.parse(trimmed);
                    root.cheatsheetLoaded = true;
                } catch (e) {
                    log.warn("Greeter: Failed to parse cheatsheet:", e);
                }
            }
        }
    }

    FocusScope {
        id: contentFocusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: event => {
            root.skip();
            event.accepted = true;
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root.currentPage < root.totalPages - 1)
                    root.nextPage();
                else
                    root.finish();
                event.accepted = true;
                break;
            case Qt.Key_Left:
                if (root.currentPage > 0)
                    root.prevPage();
                event.accepted = true;
                break;
            case Qt.Key_Right:
                if (root.currentPage < root.totalPages - 1)
                    root.nextPage();
                event.accepted = true;
                break;
            }
        }

        DWindowHeader {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            controls: windowControls
            title: root.title
            closeTooltipText: I18n.tr("Skip setup", "greeter skip button tooltip")
            onCloseRequested: root.skip()
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.bottom: footerRow.top

            Loader {
                id: pageLoader
                anchors.fill: parent
                sourceComponent: root.pageComponents[root.currentPage]

                property var greeterRoot: root
            }
        }

        Item {
            id: footerRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: Math.min(640, parent.width - Theme.spacingXL * 2)
            height: Theme.buttonHeightM + Theme.spacingL * 2
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DButton {
                    visible: root.currentPage > 0
                    text: I18n.tr("Back", "greeter back button")
                    iconName: "arrow_back"
                    buttonHeight: Theme.buttonHeightM
                    backgroundColor: Theme.secondaryContainer
                    textColor: Theme.onSecondaryContainer
                    onClicked: root.prevPage()
                }

                DButton {
                    visible: root.currentPage < root.totalPages - 1
                    text: I18n.tr("Skip", "greeter skip button")
                    buttonHeight: Theme.buttonHeightM
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: root.currentPage === 1 ? root.nextPage() : root.skip()
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS

                Repeater {
                    model: root.totalPages

                    Rectangle {
                        required property int index
                        readonly property bool isActive: index === root.currentPage

                        width: isActive ? Theme.spacingXL : Theme.spacingS
                        height: Theme.spacingS
                        radius: Theme.fullRadius(width, height)
                        color: isActive ? Theme.primary : Theme.outlineVariant
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on width {
                            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                            NumberAnimation {
                                duration: Theme.expressiveDurations.expressiveFastSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                            }
                        }

                        Behavior on color {
                            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                            ColorAnimation {
                                duration: Theme.expressiveDurations.expressiveEffects
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }
                }
            }

            DButton {
                readonly property bool lastPage: root.currentPage === root.totalPages - 1

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                enabled: !(root.currentPage === 1 && pageLoader.item && pageLoader.item.isRunning)
                text: lastPage ? I18n.tr("Finish", "greeter finish button") : root.currentPage === 0 ? I18n.tr("Get Started", "greeter first page button") : I18n.tr("Next", "greeter next button")
                iconName: lastPage ? "check" : "arrow_forward"
                buttonHeight: Theme.buttonHeightM
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: lastPage ? root.finish() : root.nextPage()
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: root
    }

    Component {
        id: welcomePage
        GreeterWelcomePage {}
    }

    Component {
        id: doctorPage
        GreeterDoctorPage {}
    }

    Component {
        id: pluginsPage
        GreeterPluginsPage {}
    }

    Component {
        id: completePage
        GreeterCompletePage {}
    }
}
