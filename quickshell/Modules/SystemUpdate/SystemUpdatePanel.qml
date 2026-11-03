import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.Common

FocusScope {
    id: updaterPanel

    property bool hostVisible: false
    property bool modalOpen: false

    signal closeRequested
    signal terminalUpgradeStarted

    focus: true
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool upgradeRunsInTerminal: SystemUpdateService.useCustomCommand || (SystemUpdateService.backends || []).some(b => b.runsInTerminal === true)
    readonly property bool showPackages: !SystemUpdateService.isUpgrading && !SystemUpdateService.isChecking && !SystemUpdateService.hasError && SystemUpdateService.helperAvailable && SystemUpdateService.updateCount > 0
    readonly property var ignoredNames: SettingsData.updaterIgnoredPackages || []
    readonly property bool offerReboot: SystemUpdateService.rebootRecommended && !SystemUpdateService.isUpgrading && !showPackages
    readonly property bool showIgnored: ignoredNames.length > 0 && !SystemUpdateService.isUpgrading && !SystemUpdateService.isChecking
    property bool ignoredExpanded: false
    property int nowUnix: Math.floor(Date.now() / 1000)

    onHostVisibleChanged: {
        if (!hostVisible)
            return;
        nowUnix = Math.floor(Date.now() / 1000);
        closeButton.forceActiveFocus();
    }

    readonly property int serviceLastCheckUnix: SystemUpdateService.lastCheckUnix

    onServiceLastCheckUnixChanged: nowUnix = Math.floor(Date.now() / 1000)

    function lastCheckedText() {
        const last = SystemUpdateService.lastCheckUnix;
        if (!last)
            return "";
        const delta = Math.max(0, nowUnix - last);
        if (delta < 90)
            return I18n.tr("checked just now");
        if (delta < 3600)
            return I18n.tr("checked %1m ago", "system update last check time, %1 is minutes").arg(Math.round(delta / 60));
        if (delta < 86400)
            return I18n.tr("checked %1h ago", "system update last check time, %1 is hours").arg(Math.round(delta / 3600));
        return I18n.tr("checked %1d ago", "system update last check time, %1 is days").arg(Math.round(delta / 86400));
    }

    function updateAll() {
        if (SystemUpdateService.isUpgrading) {
            SystemUpdateService.cancelUpdates();
            return;
        }
        if (offerReboot) {
            rebootConfirm.showWithOptions({
                title: I18n.tr("Reboot now?", "confirmation dialog title, reboot to finish a system update"),
                message: I18n.tr("Save your work first. Open apps will close.", "reboot confirmation after a system update"),
                confirmText: I18n.tr("Reboot", "verb, power menu action"),
                onConfirm: () => SessionService.reboot()
            });
            return;
        }
        const opts = {
            includeFlatpak: SettingsData.updaterIncludeFlatpak,
            includeAUR: SettingsData.updaterAllowAUR,
            terminal: SessionData.terminalOverride
        };
        if (!upgradeRunsInTerminal) {
            SystemUpdateService.runUpdates(opts);
            return;
        }
        terminalUpgradeStarted();
        SystemUpdateService.runUpdates(opts);
        closeRequested();
    }

    Keys.onEscapePressed: event => {
        if (modalOpen)
            return;
        closeRequested();
        event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PopoutMetrics.contentPadding
        spacing: PopoutMetrics.contentGap

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXS

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        switch (true) {
                        case SystemUpdateService.isUpgrading:
                            return I18n.tr("Upgrading...", "system update popout status while packages upgrade");
                        case SystemUpdateService.isChecking:
                            return I18n.tr("Checking...");
                        case SystemUpdateService.hasError:
                            return I18n.tr("Error");
                        case !SystemUpdateService.helperAvailable:
                            return I18n.tr("No supported package manager found.");
                        case SystemUpdateService.updateCount === 0:
                            return I18n.tr("Up to date");
                        case SystemUpdateService.updateCount === 1:
                            return I18n.tr("%1 update", "singular, %1 is 1, available system update count").arg(SystemUpdateService.updateCount);
                        default:
                            return I18n.tr("%1 updates", "plural, %1 is a count of available system updates").arg(SystemUpdateService.updateCount);
                        }
                    }
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: SystemUpdateService.hasError ? Theme.error : Theme.primary
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: SystemUpdateService.backends.length > 0 && !SystemUpdateService.isUpgrading
                    text: {
                        const kinds = [];
                        for (const backend of SystemUpdateService.backends || []) {
                            const label = backend.repo === "flatpak" ? "Flatpak" : I18n.tr("System");
                            if (!kinds.includes(label))
                                kinds.push(label);
                        }
                        const distro = SystemUpdateService.distributionPretty || SystemUpdateService.distribution || I18n.tr("System");
                        const checked = updaterPanel.lastCheckedText();
                        const base = distro + ": " + kinds.join(", ");
                        return checked ? base + " · " + checked : base;
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }

            DRefreshButton {
                Layout.alignment: Qt.AlignTop
                buttonSize: Theme.buttonHeightXS
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceText
                backgroundColor: Theme.foregroundColor(Theme.chipSurface)
                busy: SystemUpdateService.isChecking
                enabled: !busy && !SystemUpdateService.isUpgrading
                onClicked: SystemUpdateService.checkForUpdates()
            }
        }

        Item {
            id: bodyArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Theme.listItemTwoLineHeight

            DListView {
                id: packagesList
                anchors.fill: parent
                visible: updaterPanel.showPackages
                clip: true
                spacing: Theme.groupedListGap
                model: SystemUpdateService.availableUpdates

                delegate: DListRow {
                    id: packageRow
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    implicitHeight: Math.max(Theme.listItemTwoLineHeight, packageContent.implicitHeight + Theme.spacingS * 2)
                    firstInGroup: index === 0
                    lastInGroup: index === packagesList.count - 1
                    Accessible.name: modelData.name || ""
                    Accessible.description: versionText.text

                    RowLayout {
                        id: packageContent
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingL
                        anchors.rightMargin: Theme.spacingL
                        anchors.topMargin: Theme.spacingS
                        anchors.bottomMargin: Theme.spacingS
                        spacing: Theme.spacingM

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXXS

                            StyledText {
                                Layout.fillWidth: true
                                text: packageRow.modelData.name || ""
                                horizontalAlignment: Text.AlignLeft
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: packageRow.contentColor
                                elide: Text.ElideRight
                            }

                            StyledText {
                                id: versionText
                                Layout.fillWidth: true
                                text: {
                                    const from = packageRow.modelData.fromVersion || "";
                                    const to = packageRow.modelData.toVersion || "";
                                    const version = from && to ? from + " → " + to : to || from;
                                    const repo = packageRow.modelData.repo || "";
                                    return repo && version ? repo + " · " + version : repo || version;
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: packageRow.supportingContentColor
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideMiddle
                            }
                        }

                        DActionButton {
                            buttonSize: Theme.iconButtonSize
                            iconSize: Theme.iconSize
                            iconName: "visibility_off"
                            visible: SystemUpdateService.canIgnorePackage(packageRow.modelData)
                            tooltipText: I18n.tr("Ignore package", "tooltip, exclude a package from system updates")
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    packagesList.revealIndex(packageRow.index);
                            }
                            onClicked: SystemUpdateService.ignorePackage(packageRow.modelData.name)
                        }
                    }
                }
            }

            DFlickable {
                id: statusView
                anchors.fill: parent
                visible: !updaterPanel.showPackages && (!SystemUpdateService.isUpgrading || updaterPanel.upgradeRunsInTerminal)
                contentWidth: width
                contentHeight: Math.max(height, statusColumn.implicitHeight + Theme.spacingL * 2)
                clip: true

                Column {
                    id: statusColumn
                    x: Theme.spacingL
                    y: Math.max(Theme.spacingL, (statusView.height - implicitHeight) / 2)
                    width: statusView.width - Theme.spacingL * 2
                    spacing: Theme.spacingM

                    DIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: {
                            switch (true) {
                            case SystemUpdateService.isUpgrading:
                                return "terminal";
                            case SystemUpdateService.hasError:
                                return "error_outline";
                            case !SystemUpdateService.helperAvailable:
                                return "system_update_alt";
                            case SystemUpdateService.isChecking:
                                return "sync";
                            default:
                                return "check_circle";
                            }
                        }
                        size: Theme.iconSizeLarge
                        color: SystemUpdateService.hasError ? Theme.error : Theme.primary
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            switch (true) {
                            case SystemUpdateService.isUpgrading:
                                return I18n.tr("Running in terminal");
                            case SystemUpdateService.hasError:
                                const message = I18n.tr("Failed: %1", "system update error status, %1 is the error message").arg(SystemUpdateService.errorMessage);
                                return SystemUpdateService.errorHint ? message + "\n\n" + SystemUpdateService.errorHint : message;
                            case !SystemUpdateService.helperAvailable:
                                return I18n.tr("No supported package manager found.");
                            case SystemUpdateService.isChecking:
                                return I18n.tr("Checking for updates...");
                            default:
                                return I18n.tr("Your system is up to date!");
                            }
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: SystemUpdateService.hasError ? Theme.error : Theme.onSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    StyledText {
                        width: parent.width
                        visible: updaterPanel.offerReboot && !SystemUpdateService.hasError
                        text: I18n.tr("Reboot recommended", "chip shown after a kernel or systemd upgrade") + " · " + SystemUpdateService.rebootPackages.join(", ")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.warning
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    StyledText {
                        width: parent.width
                        visible: SystemUpdateService.isUpgrading
                        text: I18n.tr("AUR helpers are interactive — see the terminal window for prompts. This popout will return to idle when the upgrade exits.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }
            }

            DFlickable {
                id: upgradeLog
                anchors.fill: parent
                visible: SystemUpdateService.isUpgrading && !updaterPanel.upgradeRunsInTerminal
                contentWidth: width
                contentHeight: logText.implicitHeight + Theme.spacingL * 2
                clip: true
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                UpgradeLogText {
                    id: logText
                    x: Theme.spacingL
                    y: Theme.spacingL
                    width: upgradeLog.width - Theme.spacingL * 2
                    lines: upgradeLog.visible ? SystemUpdateService.recentLog : []
                }
            }
        }

        DButton {
            Layout.fillWidth: true
            visible: updaterPanel.showIgnored
            text: I18n.tr("Ignored (%1)").arg(updaterPanel.ignoredNames.length)
            iconName: updaterPanel.ignoredExpanded ? "expand_less" : "expand_more"
            backgroundColor: Theme.foregroundColor(Theme.chipSurface)
            textColor: Theme.onSurface
            maximumWidth: parent.width
            wrapText: true
            checkable: true
            checked: updaterPanel.ignoredExpanded
            onClicked: updaterPanel.ignoredExpanded = !updaterPanel.ignoredExpanded
        }

        DListView {
            id: ignoredList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, Theme.listItemHeight * 2)
            visible: updaterPanel.showIgnored && updaterPanel.ignoredExpanded
            clip: true
            spacing: Theme.groupedListGap
            model: updaterPanel.ignoredNames

            delegate: DListRow {
                id: ignoredRow
                required property string modelData
                required property int index

                width: ListView.view.width
                firstInGroup: index === 0
                lastInGroup: index === ignoredList.count - 1
                Accessible.name: modelData

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingL
                    anchors.rightMargin: Theme.spacingL
                    spacing: Theme.spacingM

                    StyledText {
                        Layout.fillWidth: true
                        text: ignoredRow.modelData
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Theme.fontSizeMedium
                        color: ignoredRow.contentColor
                        elide: Text.ElideRight
                    }

                    DActionButton {
                        buttonSize: Theme.iconButtonSize
                        iconSize: Theme.iconSize
                        iconName: "visibility"
                        tooltipText: I18n.tr("Stop ignoring %1").arg(ignoredRow.modelData)
                        onActiveFocusChanged: {
                            if (activeFocus)
                                ignoredList.revealIndex(ignoredRow.index);
                        }
                        onClicked: SystemUpdateService.unignorePackage(ignoredRow.modelData)
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            layoutDirection: Qt.RightToLeft
            spacing: Theme.spacingS

            DButton {
                text: SystemUpdateService.isUpgrading ? I18n.tr("Cancel") : updaterPanel.offerReboot ? I18n.tr("Reboot", "verb, power menu action") : I18n.tr("Update All")
                iconName: SystemUpdateService.isUpgrading ? "stop" : updaterPanel.offerReboot ? "restart_alt" : "system_update_alt"
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                maximumWidth: parent.width
                wrapText: true
                enabled: SystemUpdateService.isUpgrading || updaterPanel.showPackages || updaterPanel.offerReboot
                onClicked: updaterPanel.updateAll()
            }

            DButton {
                id: closeButton
                text: I18n.tr("Close")
                backgroundColor: "transparent"
                textColor: Theme.primary
                maximumWidth: parent.width
                wrapText: true
                focus: true
                onClicked: updaterPanel.closeRequested()
            }
        }
    }

    ConfirmDialogOverlay {
        id: rebootConfirm
    }
}
