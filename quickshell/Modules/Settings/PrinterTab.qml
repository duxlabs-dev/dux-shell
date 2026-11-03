pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: printerTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool showAddPrinter: false
    property bool manualEntryMode: false
    property string manualHost: ""
    property string manualPort: "631"
    property string manualProtocol: "ipp"
    property bool testingConnection: false
    property var testConnectionResult: null
    property string newPrinterName: ""
    property string selectedDeviceUri: ""
    property var selectedDevice: null
    property string selectedPpd: ""
    property string newPrinterLocation: ""
    property string newPrinterInfo: ""
    property var suggestedPPDs: []

    readonly property string effectiveDeviceUri: {
        if (selectedDeviceUri)
            return selectedDeviceUri;
        if (!manualEntryMode || !manualHost)
            return "";
        const port = parseInt(manualPort) || 631;
        const path = manualProtocol === "ipp" || manualProtocol === "ipps" ? "/ipp/print" : "";
        return `${manualProtocol}://${manualHost}:${port}${path}`;
    }

    function resetAddPrinterForm() {
        manualEntryMode = false;
        manualHost = "";
        manualPort = "631";
        manualProtocol = "ipp";
        testingConnection = false;
        testConnectionResult = null;
        newPrinterName = "";
        selectedDeviceUri = "";
        selectedDevice = null;
        selectedPpd = "";
        newPrinterLocation = "";
        newPrinterInfo = "";
        suggestedPPDs = [];
    }

    Ref {
        service: CupsService
    }

    Connections {
        target: CupsService
        function onPpdsChanged() {
            if (printerTab.manualEntryMode && printerTab.testConnectionResult?.success)
                printerTab.selectDriverlessPPD();
        }
    }

    function selectDriverlessPPD() {
        if (printerTab.selectedPpd || CupsService.ppds.length === 0)
            return;

        const probeModel = printerTab.testConnectionResult?.data?.makeModel || "";
        let suggested = [];

        // Try to find a model-specific PPD match
        if (probeModel) {
            const normalizedModel = probeModel.toLowerCase().replace(/[^a-z0-9]/g, "");
            const modelMatches = CupsService.ppds.filter(p => {
                const normalizedPPD = (p.makeModel || "").toLowerCase().replace(/[^a-z0-9]/g, "");
                return normalizedPPD.includes(normalizedModel) || normalizedModel.includes(normalizedPPD);
            });
            if (modelMatches.length > 0)
                suggested = suggested.concat(modelMatches);
        }

        // Always include driverless as an option
        const driverless = CupsService.ppds.filter(p => p.name === "driverless" || p.name === "everywhere");
        for (const d of driverless) {
            if (!suggested.find(s => s.name === d.name))
                suggested.push(d);
        }

        if (suggested.length > 0) {
            printerTab.selectedPpd = suggested[0].name;
            printerTab.suggestedPPDs = suggested;
        }
    }

    function selectDevice(device) {
        if (!device)
            return;
        selectedDevice = device;
        selectedDeviceUri = device.uri;
        if (!newPrinterName) {
            newPrinterName = CupsService.suggestPrinterName(device);
        }
        if (device.location && !newPrinterLocation) {
            newPrinterLocation = CupsService.decodeUri(device.location);
        }
        suggestedPPDs = CupsService.getMatchingPPDs(device);
        if (suggestedPPDs.length > 0 && !selectedPpd) {
            selectedPpd = suggestedPPDs[0].name;
        }
    }

    Component.onCompleted: {
        CupsService.getClasses();
    }

    ConfirmModal {
        id: deletePrinterConfirm
    }

    ConfirmModal {
        id: purgeJobsConfirm
    }

    ConfirmModal {
        id: deleteClassConfirm
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "print"
            title: I18n.tr("CUPS Print Server")

            SettingsRow {
                title: I18n.tr("Status", "noun, settings row or section title showing current state")
                trailingBadge: CupsService.cupsAvailable ? I18n.tr("Available") : I18n.tr("Unavailable")

                DBadge {
                    color: CupsService.cupsAvailable ? Theme.success : Theme.error
                }
            }

            SettingsRow {
                title: I18n.tr("Printers")
                trailingBadge: CupsService.printerNames.length.toString()
            }

            SettingsRow {
                title: I18n.tr("Total jobs")
                trailingBadge: CupsService.getTotalJobsNum().toString()
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "add_circle"
            title: I18n.tr("Add printer")
            visible: CupsService.cupsAvailable && printerTab.showAddPrinter

            SettingsRow {
                iconName: "add_circle"
                title: I18n.tr("Configure a new printer")

                DActionButton {
                    iconName: "close"
                    Accessible.name: I18n.tr("Cancel")
                    onClicked: {
                        printerTab.showAddPrinter = false;
                        printerTab.resetAddPrinterForm();
                    }
                }
            }

            SettingsButtonGroupRow {
                visible: printerTab.showAddPrinter
                model: [I18n.tr("Discover devices", "Toggle button to scan for printers via mDNS/Avahi"), I18n.tr("Add by address", "Toggle button to manually add a printer by IP or hostname")]
                currentIndex: printerTab.manualEntryMode ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 0:
                        printerTab.manualEntryMode = false;
                        printerTab.testConnectionResult = null;
                        printerTab.testingConnection = false;
                        return;
                    case 1:
                        printerTab.manualEntryMode = true;
                        printerTab.selectedDevice = null;
                        printerTab.selectedDeviceUri = "";
                        if (CupsService.ppds.length === 0)
                            CupsService.getPPDs();
                        return;
                    }
                }
            }

            SettingsDropdownRow {
                visible: printerTab.showAddPrinter && !printerTab.manualEntryMode
                text: I18n.tr("Device")
                description: printerTab.selectedDevice !== null ? CupsService.getDeviceSubtitle(printerTab.selectedDevice) : ""
                dropdownWidth: width / 2
                popupWidth: width / 2
                enableFuzzySearch: true
                emptyText: I18n.tr("No devices found")
                currentValue: {
                    if (CupsService.loadingDevices)
                        return I18n.tr("Scanning...", "status while searching for printers, wifi networks or bluetooth devices");
                    if (printerTab.selectedDevice)
                        return CupsService.getDeviceDisplayName(printerTab.selectedDevice);
                    return I18n.tr("Select device", "printer device dropdown placeholder") + "…";
                }
                options: CupsService.filteredDevices.map(d => CupsService.getDeviceDisplayName(d))
                onValueChanged: value => {
                    const filtered = CupsService.filteredDevices;
                    const device = filtered.find(d => CupsService.getDeviceDisplayName(d) === value);
                    if (device)
                        printerTab.selectDevice(device);
                }

                DRefreshButton {
                    buttonSize: 32
                    anchors.verticalCenter: parent.verticalCenter
                    busy: CupsService.loadingDevices
                    onClicked: CupsService.getDevices()
                }
            }

            SettingsTextFieldRow {
                visible: printerTab.showAddPrinter && printerTab.manualEntryMode
                leftIconName: "dns"
                text: I18n.tr("Host", "Label for printer IP address or hostname input field")
                placeholderText: I18n.tr("IP address or hostname", "Placeholder text for manual printer address input")
                value: printerTab.manualHost
                onValueEdited: value => {
                    printerTab.manualHost = value;
                    printerTab.selectedDeviceUri = "";
                    printerTab.testConnectionResult = null;
                }
            }

            SettingsTextFieldRow {
                visible: printerTab.showAddPrinter && printerTab.manualEntryMode
                leftIconName: "settings_ethernet"
                text: I18n.tr("Port", "Label for printer port number input field")
                placeholderText: "631"
                value: printerTab.manualPort
                onValueEdited: value => {
                    printerTab.manualPort = value;
                    printerTab.selectedDeviceUri = "";
                    printerTab.testConnectionResult = null;
                }
            }

            SettingsDropdownRow {
                visible: printerTab.showAddPrinter && printerTab.manualEntryMode
                text: I18n.tr("Protocol", "Label for printer protocol selector, e.g. ipp, ipps, lpd, socket")
                dropdownWidth: 120
                popupWidth: 120
                currentValue: printerTab.manualProtocol
                options: ["ipp", "ipps", "lpd", "socket"]
                onValueChanged: value => {
                    printerTab.manualProtocol = value;
                    printerTab.selectedDeviceUri = "";
                    printerTab.testConnectionResult = null;
                }
            }

            SettingsRow {
                readonly property var result: printerTab.testConnectionResult
                readonly property bool reachable: !!result?.success

                visible: printerTab.showAddPrinter && printerTab.manualEntryMode
                title: result !== null ? (reachable ? I18n.tr("Printer reachable", "Status message when test connection to printer succeeds") : I18n.tr("Connection failed", "Status message when test connection to printer fails")) : ""
                titleColor: reachable ? Theme.success : Theme.error
                subtitle: {
                    const details = reachable ? (result?.data?.makeModel || result?.data?.info || "") : "";
                    const error = result?.data?.error || result?.error || "";
                    return [details, error].filter(line => line !== "").join("\n");
                }
                leading: DBadge {
                    visible: printerTab.testConnectionResult !== null
                    color: printerTab.testConnectionResult?.success ? Theme.success : Theme.error
                }

                DButton {
                    text: printerTab.testingConnection ? I18n.tr("Testing...", "Button state while testing printer connection") : I18n.tr("Test connection", "Button to test connection to a printer by IP address")
                    iconName: printerTab.testingConnection ? "sync" : "lan"
                    buttonHeight: 36
                    enabled: printerTab.manualHost.length > 0 && !printerTab.testingConnection
                    onClicked: {
                        printerTab.testingConnection = true;
                        printerTab.testConnectionResult = null;
                        const port = parseInt(printerTab.manualPort) || 631;
                        CupsService.testConnection(printerTab.manualHost, port, printerTab.manualProtocol, response => {
                            printerTab.testingConnection = false;
                            if (response.error) {
                                printerTab.testConnectionResult = {
                                    "success": false,
                                    "error": response.error
                                };
                            } else if (response.result) {
                                printerTab.testConnectionResult = {
                                    "success": response.result.reachable === true,
                                    "data": response.result
                                };
                                if (response.result.reachable) {
                                    if (response.result.uri)
                                        printerTab.selectedDeviceUri = response.result.uri;
                                    if (response.result.name && !printerTab.newPrinterName)
                                        printerTab.newPrinterName = response.result.name.replace(/[^a-zA-Z0-9_-]/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").substring(0, 32) || "Printer";
                                    if (CupsService.ppds.length === 0) {
                                        CupsService.getPPDs();
                                    }
                                    selectDriverlessPPD();
                                }
                            }
                        });
                    }
                }
            }

            SettingsDropdownRow {
                visible: printerTab.showAddPrinter
                text: I18n.tr("Driver", "noun, printer driver dropdown label and network device driver detail label")
                dropdownWidth: width / 2
                popupWidth: width / 2
                enableFuzzySearch: true
                emptyText: I18n.tr("No drivers found")
                currentValue: {
                    if (CupsService.loadingPPDs)
                        return I18n.tr("Loading...");
                    if (printerTab.selectedPpd) {
                        const ppd = CupsService.ppds.find(p => p.name === printerTab.selectedPpd);
                        if (ppd) {
                            const isSuggested = printerTab.suggestedPPDs.some(s => s.name === ppd.name);
                            return (isSuggested ? "★ " : "") + (ppd.makeModel || ppd.name);
                        }
                        return printerTab.selectedPpd;
                    }
                    return printerTab.suggestedPPDs.length > 0 ? I18n.tr("Recommended available") : I18n.tr("Select driver...");
                }
                options: {
                    const suggested = printerTab.suggestedPPDs.map(p => "★ " + (p.makeModel || p.name));
                    const others = CupsService.ppds.filter(p => !printerTab.suggestedPPDs.some(s => s.name === p.name)).map(p => p.makeModel || p.name);
                    return suggested.concat(others);
                }
                onValueChanged: value => {
                    const cleanValue = value.replace(/^★ /, "");
                    const ppd = CupsService.ppds.find(p => (p.makeModel || p.name) === cleanValue);
                    if (ppd)
                        printerTab.selectedPpd = ppd.name;
                }

                DRefreshButton {
                    buttonSize: 32
                    anchors.verticalCenter: parent.verticalCenter
                    busy: CupsService.loadingPPDs
                    onClicked: CupsService.getPPDs()
                }
            }

            SettingsTextFieldRow {
                visible: printerTab.showAddPrinter
                leftIconName: "print"
                text: I18n.tr("Name")
                placeholderText: I18n.tr("Printer name (no spaces)")
                value: printerTab.newPrinterName
                onValueEdited: value => printerTab.newPrinterName = value.replace(/\s/g, "-")
            }

            SettingsTextFieldRow {
                visible: printerTab.showAddPrinter
                leftIconName: "location_on"
                text: I18n.tr("Location", "noun, physical place of a printer, text field label")
                placeholderText: I18n.tr("Optional location")
                value: printerTab.newPrinterLocation
                onValueEdited: value => printerTab.newPrinterLocation = value
            }

            SettingsTextFieldRow {
                visible: printerTab.showAddPrinter
                leftIconName: "description"
                text: I18n.tr("Description")
                placeholderText: I18n.tr("Optional description")
                value: printerTab.newPrinterInfo
                onValueEdited: value => printerTab.newPrinterInfo = value
            }

            SettingsRow {
                visible: printerTab.showAddPrinter
                body: Row {
                    LayoutMirroring.enabled: false
                    width: parent.width
                    layoutDirection: Qt.RightToLeft

                    DButton {
                        text: CupsService.creatingPrinter ? I18n.tr("Creating...", "create printer button label while the printer is being added") : I18n.tr("Create printer")
                        iconName: CupsService.creatingPrinter ? "sync" : "add"
                        buttonHeight: 36
                        enabled: printerTab.newPrinterName.length > 0 && printerTab.effectiveDeviceUri.length > 0 && printerTab.selectedPpd.length > 0 && !CupsService.creatingPrinter
                        onClicked: {
                            CupsService.createPrinter(printerTab.newPrinterName, printerTab.effectiveDeviceUri, printerTab.selectedPpd, {
                                location: printerTab.newPrinterLocation,
                                information: printerTab.newPrinterInfo
                            });
                            printerTab.resetAddPrinterForm();
                            printerTab.showAddPrinter = false;
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "print"
            title: I18n.tr("Installed")
            visible: CupsService.cupsAvailable

            headerActions: [
                StyledText {
                    text: {
                        const count = CupsService.printerNames.length;
                        if (count === 0)
                            return I18n.tr("No printers configured");
                        return (count === 1 ? I18n.tr("%1 printer", "singular, %1 is 1, printer count") : I18n.tr("%1 printers", "plural, %1 is a count of printers")).arg(count);
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                },
                DActionButton {
                    iconName: "refresh"
                    Accessible.name: I18n.tr("Refresh")
                    buttonSize: 32
                    onClicked: CupsService.getState()
                }
            ]

            SettingsRow {
                visible: CupsService.printerNames.length === 0
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    DIcon {
                        name: "print_disabled"
                        size: 32
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: I18n.tr("No printer found", "empty state in printer list")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            Repeater {
                model: CupsService.printerNames

                delegate: Column {
                    id: printerDelegate
                    required property string modelData
                    required property int index

                    readonly property var printerData: CupsService.getPrinterData(modelData)
                    readonly property bool isExpanded: CupsService.expandedPrinter === modelData || hasJobs
                    readonly property bool hasJobs: (printerData?.jobs?.length ?? 0) > 0
                    readonly property bool isIdle: printerData?.state === "idle"
                    readonly property bool isStopped: printerData?.state === "stopped"

                    width: parent?.width ?? 0
                    spacing: SettingsMetrics.groupGap

                    SettingsRow {
                        iconName: printerDelegate.isStopped ? "print_disabled" : "print"
                        iconColor: printerDelegate.isStopped ? Theme.error : (printerDelegate.isIdle ? Theme.primary : Theme.warning)
                        title: printerDelegate.modelData
                        titleColor: CupsService.selectedPrinter === printerDelegate.modelData ? Theme.primary : Theme.surfaceText
                        subtitle: CupsService.getPrinterStateTranslation(printerDelegate.printerData?.state || "")
                        subtitleColor: {
                            switch (printerDelegate.printerData?.state) {
                            case "idle":
                                return Theme.primary;
                            case "stopped":
                                return Theme.error;
                            case "processing":
                                return Theme.warning;
                            default:
                                return Theme.surfaceVariantText;
                            }
                        }
                        trailingBadge: printerDelegate.hasJobs ? ((printerDelegate.printerData?.jobs?.length ?? 0) === 1 ? I18n.tr("%1 job", "singular, %1 is 1, print job count badge") : I18n.tr("%1 jobs", "plural, %1 is a count of print jobs")).arg(printerDelegate.printerData?.jobs?.length ?? 0) : ""
                        clickable: true
                        onClicked: CupsService.setSelectedPrinter(printerDelegate.modelData)

                        DActionButton {
                            iconName: printerDelegate.isExpanded ? "expand_less" : "expand_more"
                            Accessible.name: printerDelegate.isExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                            onClicked: {
                                CupsService.expandedPrinter = printerDelegate.isExpanded ? "" : printerDelegate.modelData;
                            }
                        }

                        DActionButton {
                            iconName: "delete"
                            Accessible.name: I18n.tr("Delete")
                            onClicked: {
                                deletePrinterConfirm.showWithOptions({
                                    title: I18n.tr("Delete printer"),
                                    message: I18n.tr("Delete \"%1\"?").arg(printerDelegate.modelData),
                                    confirmText: I18n.tr("Delete"),
                                    confirmColor: Theme.error,
                                    onConfirm: () => CupsService.deletePrinter(printerDelegate.modelData)
                                });
                            }
                        }
                    }

                    SettingsRow {
                        visible: printerDelegate.isExpanded
                        body: Column {
                            width: parent.width
                            spacing: Theme.spacingS

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: {
                                        const fields = [];
                                        const p = printerDelegate.printerData;
                                        if (!p)
                                            return fields;

                                        fields.push({
                                            label: I18n.tr("State", "noun, detail label for printer or network device status"),
                                            value: CupsService.getPrinterStateTranslation(p.state)
                                        });
                                        if (p.stateReason && p.stateReason !== "none")
                                            fields.push({
                                                label: I18n.tr("Reason", "printer detail label, reason for the current printer state"),
                                                value: CupsService.getPrinterStateReasonTranslation(p.stateReason)
                                            });
                                        if (p.makeModel)
                                            fields.push({
                                                label: I18n.tr("Model"),
                                                value: p.makeModel
                                            });
                                        if (p.location)
                                            fields.push({
                                                label: I18n.tr("Location"),
                                                value: p.location
                                            });
                                        fields.push({
                                            label: I18n.tr("Accepting", "printer detail label, whether the printer accepts jobs, value is yes or no"),
                                            value: p.accepting ? I18n.tr("Yes") : I18n.tr("No")
                                        });

                                        return fields;
                                    }

                                    delegate: DDetailChip {
                                        required property var modelData

                                        label: modelData.label
                                        value: modelData.value
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                DButton {
                                    text: printerDelegate.isStopped ? I18n.tr("Resume", "verb, button that resumes a paused printer") : I18n.tr("Pause")
                                    iconName: printerDelegate.isStopped ? "play_arrow" : "pause"
                                    buttonHeight: Theme.buttonHeightXS
                                    backgroundColor: SettingsMetrics.controlSurface
                                    textColor: Theme.surfaceText
                                    onClicked: {
                                        if (printerDelegate.isStopped) {
                                            CupsService.resumePrinter(printerDelegate.modelData);
                                        } else {
                                            CupsService.pausePrinter(printerDelegate.modelData);
                                        }
                                    }
                                }

                                DButton {
                                    text: I18n.tr("Test page")
                                    iconName: "description"
                                    buttonHeight: Theme.buttonHeightXS
                                    backgroundColor: SettingsMetrics.controlSurface
                                    textColor: Theme.surfaceText
                                    onClicked: CupsService.printTestPage(printerDelegate.modelData)
                                }

                                DButton {
                                    text: printerDelegate.printerData?.accepting ? I18n.tr("Reject jobs") : I18n.tr("Accept jobs")
                                    iconName: printerDelegate.printerData?.accepting ? "block" : "check_circle"
                                    buttonHeight: Theme.buttonHeightXS
                                    backgroundColor: SettingsMetrics.controlSurface
                                    textColor: Theme.surfaceText
                                    onClicked: {
                                        if (printerDelegate.printerData?.accepting) {
                                            CupsService.rejectJobs(printerDelegate.modelData);
                                        } else {
                                            CupsService.acceptJobs(printerDelegate.modelData);
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS
                                visible: (printerDelegate.printerData?.jobs?.length ?? 0) > 0

                                StyledText {
                                    text: I18n.tr("Jobs", "noun, print jobs section label")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DButton {
                                    text: I18n.tr("Clear All")
                                    iconName: "delete_sweep"
                                    buttonHeight: Theme.buttonHeightXS
                                    backgroundColor: SettingsMetrics.controlSurface
                                    textColor: Theme.surfaceText
                                    onClicked: {
                                        purgeJobsConfirm.showWithOptions({
                                            title: I18n.tr("Clear all jobs"),
                                            message: I18n.tr("Cancel all jobs for \"%1\"?", "confirm dialog message, %1 is the printer name").arg(printerDelegate.modelData),
                                            confirmText: I18n.tr("Clear"),
                                            confirmColor: Theme.error,
                                            onConfirm: () => CupsService.purgeJobs(printerDelegate.modelData)
                                        });
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: printerDelegate.printerData?.jobs ?? []

                        delegate: SettingsRow {
                            id: jobRow
                            required property var modelData
                            required property int index

                            visible: printerDelegate.isExpanded
                            iconName: "description"
                            iconColor: Theme.surfaceVariantText
                            title: "[" + modelData.id + "] " + CupsService.getJobStateTranslation(modelData.state)
                            subtitle: {
                                const size = Math.round((modelData.size || 0) / 1024);
                                const date = new Date(modelData.timeCreated);
                                return size + " KB • " + date.toLocaleString(Qt.locale(), Locale.ShortFormat);
                            }

                            DActionButton {
                                visible: jobRow.modelData.state === "pending"
                                iconName: "pause"
                                Accessible.name: I18n.tr("Pause")
                                onClicked: CupsService.holdJob(jobRow.modelData.id)
                            }

                            DActionButton {
                                visible: jobRow.modelData.state === "pending-held" || jobRow.modelData.state === "completed" || jobRow.modelData.state === "aborted"
                                iconName: "replay"
                                tooltipText: I18n.tr("Retry")
                                onClicked: CupsService.restartJob(jobRow.modelData.id)
                            }

                            DActionButton {
                                iconName: "close"
                                Accessible.name: I18n.tr("Cancel")
                                onClicked: CupsService.cancelJob(printerDelegate.modelData, jobRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "workspaces"
            title: I18n.tr("Classes", "printer settings card title, cups printer classes")
            visible: CupsService.cupsAvailable && CupsService.printerClasses.length > 0

            headerActions: [
                StyledText {
                    text: (CupsService.printerClasses.length === 1 ? I18n.tr("%1 class", "singular, %1 is 1, printer class count") : I18n.tr("%1 classes", "plural, %1 is a count of printer classes")).arg(CupsService.printerClasses.length)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                },
                DActionButton {
                    iconName: "refresh"
                    Accessible.name: I18n.tr("Refresh")
                    buttonSize: 32
                    onClicked: CupsService.getClasses()
                }
            ]

            Repeater {
                model: CupsService.printerClasses

                delegate: SettingsRow {
                    id: classRow
                    required property var modelData
                    required property int index

                    iconName: "workspaces"
                    iconColor: Theme.surfaceText
                    title: modelData.name || I18n.tr("Unknown")
                    subtitle: ((modelData.members?.length ?? 0) === 1 ? I18n.tr("%1 printer") : I18n.tr("%1 printers")).arg(modelData.members?.length ?? 0)

                    DActionButton {
                        iconName: "delete"
                        Accessible.name: I18n.tr("Delete")
                        onClicked: {
                            deleteClassConfirm.showWithOptions({
                                title: I18n.tr("Delete class"),
                                message: I18n.tr("Delete class \"%1\"?", "confirm dialog message, %1 is the printer class name").arg(classRow.modelData.name),
                                confirmText: I18n.tr("Delete"),
                                confirmColor: Theme.error,
                                onConfirm: () => CupsService.deleteClass(classRow.modelData.name)
                            });
                        }
                    }
                }
            }
        }

        SettingsFabBar {
            shown: CupsService.cupsAvailable && !printerTab.showAddPrinter

            DFab {
                text: I18n.tr("Add printer")
                iconName: "add"
                onClicked: {
                    printerTab.showAddPrinter = true;
                    if (CupsService.devices.length === 0) {
                        CupsService.getDevices();
                        CupsService.getPPDs();
                    }
                    mainColumn.contentY = 0;
                }
            }
        }
    }
}
