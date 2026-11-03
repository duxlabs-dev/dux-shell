pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("CupsService")

    property int refCount: 0

    onRefCountChanged: {
        if (refCount > 0) {
            ensureSubscription();
        } else if (refCount === 0 && DMSService.activeSubscriptions.includes("cups")) {
            DMSService.removeSubscription("cups");
        }
    }

    function ensureSubscription() {
        if (refCount <= 0)
            return;
        if (!DMSService.isConnected)
            return;
        if (DMSService.activeSubscriptions.includes("cups"))
            return;
        if (DMSService.activeSubscriptions.includes("all"))
            return;
        DMSService.addSubscription("cups");
        if (cupsAvailable) {
            getState();
        }
    }

    property var printerNames: []
    property var printers: []
    property string selectedPrinter: ""
    property string expandedPrinter: ""

    property bool cupsAvailable: false
    property bool stateInitialized: false

    property var devices: []
    property var ppds: []
    property var printerClasses: []

    readonly property var filteredDevices: {
        if (!devices || devices.length === 0)
            return [];
        const bareProtocols = ["ipp", "ipps", "http", "https", "lpd", "socket", "beh", "dnssd", "mdns", "smb", "file", "cups-brf"];

        // First pass: filter out invalid/bare protocol entries
        const validDevices = devices.filter(d => {
            if (!d.uri)
                return false;
            const uriLower = d.uri.toLowerCase();
            for (let proto of bareProtocols) {
                if (uriLower === proto || uriLower === proto + ":")
                    return false;
            }
            if (d.class === "network" && d.info === "Backend Error Handler")
                return false;
            return true;
        });

        // Second pass: prefer IPP over LPD for the same printer
        // _printer._tcp (LPD) doesn't work well with driverless printing
        // _ipp._tcp or _ipps._tcp (IPP) should be preferred
        const ippDeviceHosts = new Set();
        for (const d of validDevices) {
            if (!d.uri)
                continue;
            // Extract hostname from dnssd URIs like dnssd://Name%20[mac]._ipp._tcp.local
            const ippMatch = d.uri.match(/dnssd:\/\/[^/]*\._ipps?\._tcp/);
            if (ippMatch) {
                // Extract the unique identifier (usually MAC address in brackets)
                const macMatch = d.uri.match(/\[([a-f0-9]+)\]/i);
                if (macMatch)
                    ippDeviceHosts.add(macMatch[1].toLowerCase());
            }
        }

        // Filter out _printer._tcp devices when we have _ipp._tcp for the same printer
        return validDevices.filter(d => {
            if (!d.uri)
                return true;
            // If this is an LPD device, check if we have an IPP alternative
            if (d.uri.includes("._printer._tcp")) {
                const macMatch = d.uri.match(/\[([a-f0-9]+)\]/i);
                if (macMatch && ippDeviceHosts.has(macMatch[1].toLowerCase())) {
                    return false; // Skip LPD device, we have IPP
                }
            }
            return true;
        });
    }

    function decodeUri(str) {
        if (!str)
            return "";
        try {
            return decodeURIComponent(str.replace(/\+/g, " "));
        } catch (e) {
            return str;
        }
    }

    function getDeviceDisplayName(device) {
        if (!device)
            return "";
        let name = "";
        if (device.info && device.info.length > 0) {
            name = decodeUri(device.info);
        } else if (device.makeModel && device.makeModel.length > 0) {
            name = decodeUri(device.makeModel);
        } else {
            return decodeUri(device.uri);
        }
        if (device.ip)
            return name + " (" + device.ip + ")";
        return name;
    }

    function getDeviceSubtitle(device) {
        if (!device)
            return "";
        const parts = [];
        switch (device.class) {
        case "direct":
            parts.push(I18n.tr("Local", "adjective, directly attached printer device class"));
            break;
        case "network":
            parts.push(I18n.tr("Network", "printer device class, a network printer"));
            break;
        case "file":
            parts.push(I18n.tr("File"));
            break;
        default:
            if (device.class)
                parts.push(device.class);
        }
        if (device.location)
            parts.push(decodeUri(device.location));
        return parts.join(" • ");
    }

    function suggestPrinterName(device) {
        if (!device)
            return "";
        let name = device.info || device.makeModel || "";
        name = name.replace(/[^a-zA-Z0-9_-]/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
        return name.substring(0, 32) || "Printer";
    }

    function getMatchingPPDs(device) {
        if (!device || !ppds || ppds.length === 0)
            return [];
        const isDnssd = device.uri && (device.uri.startsWith("dnssd://") || device.uri.startsWith("ipp://") || device.uri.startsWith("ipps://"));
        if (isDnssd) {
            const driverless = ppds.filter(p => p.name === "driverless" || p.name === "everywhere" || (p.makeModel && p.makeModel.toLowerCase().includes("driverless")));
            if (driverless.length > 0)
                return driverless;
        }
        if (!device.makeModel)
            return [];
        const makeModelLower = device.makeModel.toLowerCase();
        const words = makeModelLower.split(/[\s_-]+/).filter(w => w.length > 2);
        return ppds.filter(p => {
            if (!p.makeModel)
                return false;
            const ppdLower = p.makeModel.toLowerCase();
            return words.some(w => ppdLower.includes(w));
        }).slice(0, 10);
    }

    property bool loadingDevices: false
    property bool loadingPPDs: false
    property bool loadingClasses: false
    property bool creatingPrinter: false

    signal cupsStateUpdate

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0) {
            checkDMSCapabilities();
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
                ensureSubscription();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onCupsStateUpdate(data) {
            log.debug("Subscription update received");
            getState();
        }

        function onCapabilitiesChanged() {
            checkDMSCapabilities();
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected)
            return;
        if (DMSService.capabilities.length === 0)
            return;
        cupsAvailable = DMSService.capabilities.includes("cups");

        if (refCount <= 0)
            return;
        if (cupsAvailable && !stateInitialized) {
            stateInitialized = true;
            getState();
        }
    }

    function getState() {
        if (!cupsAvailable)
            return;
        DMSService.sendRequest("cups.getPrinters", null, response => {
            if (response.result) {
                updatePrinters(response.result);
                fetchAllJobs();
            }
        });
    }

    function updatePrinters(printersData) {
        printerNames = printersData.map(p => p.name);

        let printersObj = {};
        for (var i = 0; i < printersData.length; i++) {
            let printer = printersData[i];
            printersObj[printer.name] = {
                "name": printer.name,
                "uri": printer.uri || "",
                "state": printer.state,
                "stateReason": printer.stateReason,
                "location": printer.location || "",
                "info": printer.info || "",
                "makeModel": printer.makeModel || "",
                "accepting": printer.accepting !== false,
                "jobs": []
            };
        }
        printers = printersObj;

        if (printerNames.length > 0) {
            if (selectedPrinter.length > 0) {
                if (!printerNames.includes(selectedPrinter)) {
                    selectedPrinter = printerNames[0];
                }
            } else {
                selectedPrinter = printerNames[0];
            }
        }
    }

    function fetchAllJobs() {
        for (var i = 0; i < printerNames.length; i++) {
            fetchJobsForPrinter(printerNames[i]);
        }
    }

    function fetchJobsForPrinter(printerName) {
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.getJobs", params, response => {
            if (response.result && printers[printerName]) {
                let updatedPrinters = Object.assign({}, printers);
                updatedPrinters[printerName].jobs = response.result;
                printers = updatedPrinters;
            }
        });
    }

    function getSelectedPrinter() {
        return selectedPrinter;
    }

    function setSelectedPrinter(printerName) {
        if (printerNames.length > 0) {
            if (printerNames.includes(printerName)) {
                selectedPrinter = printerName;
            } else {
                selectedPrinter = printerNames[0];
            }
        }
    }

    function getPrintersNum() {
        if (!cupsAvailable)
            return 0;

        return printerNames.length;
    }

    function getPrintersNames() {
        if (!cupsAvailable)
            return [];

        return printerNames;
    }

    function getTotalJobsNum() {
        if (!cupsAvailable)
            return 0;

        var result = 0;
        for (var i = 0; i < printerNames.length; i++) {
            var printerName = printerNames[i];
            if (printers[printerName] && printers[printerName].jobs) {
                result += printers[printerName].jobs.length;
            }
        }
        return result;
    }

    function getCurrentPrinterState() {
        if (!cupsAvailable || !selectedPrinter)
            return "";

        var printer = printers[selectedPrinter];
        return printer.state;
    }

    function getCurrentPrinterStatePrettyShort() {
        if (!cupsAvailable || !selectedPrinter)
            return "";

        var printer = printers[selectedPrinter];
        return getPrinterStateTranslation(printer.state) + " (" + getPrinterStateReasonTranslation(printer.stateReason) + ")";
    }

    function getCurrentPrinterJobs() {
        if (!cupsAvailable || !selectedPrinter)
            return [];

        return getJobs(selectedPrinter);
    }

    function getJobs(printerName) {
        if (!cupsAvailable)
            return "";

        var printer = printers[printerName];
        return printer.jobs;
    }

    function pausePrinter(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.pausePrinter", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to pause printer"), response.error);
            } else {
                getState();
            }
        });
    }

    function resumePrinter(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.resumePrinter", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to resume printer"), response.error);
            } else {
                getState();
            }
        });
    }

    function cancelJob(printerName, jobID) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName,
            "jobID": jobID
        };

        DMSService.sendRequest("cups.cancelJob", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to cancel selected job"), response.error);
            } else {
                fetchJobsForPrinter(printerName);
            }
        });
    }

    function purgeJobs(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.purgeJobs", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to cancel all jobs"), response.error);
            } else {
                fetchJobsForPrinter(printerName);
            }
        });
    }

    function getDevices() {
        if (!cupsAvailable)
            return;
        loadingDevices = true;
        DMSService.sendRequest("cups.getDevices", null, response => {
            loadingDevices = false;
            if (response.result) {
                devices = response.result;
            }
        });
    }

    function getPPDs() {
        if (!cupsAvailable)
            return;
        loadingPPDs = true;
        DMSService.sendRequest("cups.getPPDs", null, response => {
            loadingPPDs = false;
            if (response.result) {
                ppds = response.result;
            }
        });
    }

    function getClasses() {
        if (!cupsAvailable)
            return;
        loadingClasses = true;
        DMSService.sendRequest("cups.getClasses", null, response => {
            loadingClasses = false;
            if (response.result) {
                printerClasses = response.result;
            }
        });
    }

    function testConnection(host, port, protocol, callback) {
        if (!cupsAvailable)
            return;
        const params = {
            "host": host,
            "port": port,
            "protocol": protocol
        };

        DMSService.sendRequest("cups.testConnection", params, response => {
            if (callback)
                callback(response);
        });
    }

    function createPrinter(name, deviceURI, ppd, options) {
        if (!cupsAvailable)
            return;
        creatingPrinter = true;
        const params = {
            "name": name,
            "deviceURI": deviceURI,
            "ppd": ppd
        };
        if (options) {
            if (options.shared !== undefined)
                params.shared = options.shared;
            if (options.location)
                params.location = options.location;
            if (options.information)
                params.information = options.information;
            if (options.errorPolicy)
                params.errorPolicy = options.errorPolicy;
        }

        DMSService.sendRequest("cups.createPrinter", params, response => {
            creatingPrinter = false;
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to create printer"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("Printer created successfully"));
                getState();
            }
        });
    }

    function deletePrinter(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.deletePrinter", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to delete printer"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("Printer deleted"));
                if (selectedPrinter === printerName) {
                    selectedPrinter = "";
                }
                getState();
            }
        });
    }

    function acceptJobs(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.acceptJobs", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to enable job acceptance"), response.error);
            } else {
                getState();
            }
        });
    }

    function rejectJobs(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.rejectJobs", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to disable job acceptance"), response.error);
            } else {
                getState();
            }
        });
    }

    function printTestPage(printerName) {
        if (!cupsAvailable)
            return;
        const params = {
            "printerName": printerName
        };

        DMSService.sendRequest("cups.printTestPage", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to print test page"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("Test page sent to printer"));
                fetchJobsForPrinter(printerName);
            }
        });
    }

    function restartJob(jobID) {
        if (!cupsAvailable)
            return;
        const params = {
            "jobID": jobID
        };

        DMSService.sendRequest("cups.restartJob", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to restart job"), response.error);
            } else {
                fetchAllJobs();
            }
        });
    }

    function holdJob(jobID, holdUntil) {
        if (!cupsAvailable)
            return;
        const params = {
            "jobID": jobID
        };
        if (holdUntil) {
            params.holdUntil = holdUntil;
        }

        DMSService.sendRequest("cups.holdJob", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to hold job"), response.error);
            } else {
                fetchAllJobs();
            }
        });
    }

    function deleteClass(className) {
        if (!cupsAvailable)
            return;
        const params = {
            "className": className
        };

        DMSService.sendRequest("cups.deleteClass", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to delete class"), response.error);
            } else {
                getClasses();
            }
        });
    }

    function getPrinterData(printerName) {
        if (!printers || !printers[printerName])
            return null;
        return printers[printerName];
    }

    function getJobStateTranslation(state) {
        switch (state) {
        case "pending":
            return I18n.tr("Pending", "printer job state");
        case "pending-held":
            return I18n.tr("Held", "printer job state, job is on hold");
        case "processing":
            return I18n.tr("Processing", "printer job state, also printer state");
        case "processing-stopped":
            return I18n.tr("Stopped", "printer job state, also printer state");
        case "canceled":
            return I18n.tr("Canceled", "printer job state");
        case "aborted":
            return I18n.tr("Aborted", "printer job state");
        case "completed":
            return I18n.tr("Completed", "printer job state");
        default:
            return state;
        }
    }

    readonly property var states: ({
            "idle": I18n.tr("Idle", "adjective, printer state", true),
            "processing": I18n.tr("Processing"),
            "stopped": I18n.tr("Stopped")
        })

    readonly property var reasonsGeneral: ({
            "none": I18n.tr("None"),
            "other": I18n.tr("Other", "printer state reason")
        })

    readonly property var reasonsSupplies: ({
            "toner-low": I18n.tr("Toner Low"),
            "toner-empty": I18n.tr("Toner Empty"),
            "marker-supply-low": I18n.tr("Marker Supply Low"),
            "marker-supply-empty": I18n.tr("Marker Supply Empty"),
            "marker-waste-almost-full": I18n.tr("Marker Waste Almost Full"),
            "marker-waste-full": I18n.tr("Marker Waste Full")
        })

    readonly property var reasonsMedia: ({
            "media-low": I18n.tr("Media Low"),
            "media-empty": I18n.tr("Media Empty"),
            "media-needed": I18n.tr("Media Needed"),
            "media-jam": I18n.tr("Media Jam")
        })

    readonly property var reasonsParts: ({
            "cover-open": I18n.tr("Cover Open"),
            "door-open": I18n.tr("Door Open"),
            "interlock-open": I18n.tr("Interlock Open"),
            "output-tray-missing": I18n.tr("Output Tray Missing"),
            "output-area-almost-full": I18n.tr("Output Area Almost Full"),
            "output-area-full": I18n.tr("Output Area Full")
        })

    readonly property var reasonsErrors: ({
            "paused": I18n.tr("Paused", "printer state reason"),
            "shutdown": I18n.tr("Shutdown", "printer state reason, the printer has shut down"),
            "connecting-to-device": I18n.tr("Connecting to Device"),
            "timed-out": I18n.tr("Timed Out"),
            "stopping": I18n.tr("Stopping", "printer state reason"),
            "stopped-partly": I18n.tr("Stopped Partly")
        })

    readonly property var reasonsService: ({
            "spool-area-full": I18n.tr("Spool Area Full"),
            "cups-missing-filter-warning": I18n.tr("CUPS Missing Filter Warning"),
            "cups-insecure-filter-warning": I18n.tr("CUPS Insecure Filter Warning")
        })

    readonly property var reasonsConnectivity: ({
            "offline-report": I18n.tr("Offline Report"),
            "moving-to-paused": I18n.tr("Moving to Paused")
        })

    readonly property var severitySuffixes: ({
            "-error": I18n.tr("Error"),
            "-warning": I18n.tr("Warning", "noun, printer state reason severity"),
            "-report": I18n.tr("Report", "noun, printer state reason severity")
        })

    function getPrinterStateTranslation(state) {
        return states[state] || state;
    }

    function getPrinterStateReasonTranslation(reason) {
        let allReasons = Object.assign({}, reasonsGeneral, reasonsSupplies, reasonsMedia, reasonsParts, reasonsErrors, reasonsService, reasonsConnectivity);

        let basReason = reason;
        let suffix = "";

        for (let s in severitySuffixes) {
            if (reason.endsWith(s)) {
                basReason = reason.slice(0, -s.length);
                suffix = severitySuffixes[s];
                break;
            }
        }

        let translation = allReasons[basReason] || basReason;
        return suffix ? translation + " (" + suffix + ")" : translation;
    }
}
