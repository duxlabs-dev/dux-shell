pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/OutputModel.js" as OutputModel

Singleton {
    id: root
    readonly property var log: Log.scoped("WlrOutputService")

    property bool wlrOutputAvailable: false
    property var outputs: []
    property int serial: 0

    signal stateChanged
    signal configurationApplied(bool success, string message)

    Connections {
        target: DMSService

        function onCapabilitiesReceived() {
            checkCapabilities();
        }

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkCapabilities();
                return;
            }
            wlrOutputAvailable = false;
        }

        function onWlrOutputStateUpdate(data) {
            if (!wlrOutputAvailable) {
                return;
            }
            handleStateUpdate(data);
        }
    }

    Component.onCompleted: {
        if (!DMSService.dmsAvailable) {
            return;
        }
        checkCapabilities();
    }

    function checkCapabilities() {
        if (!DMSService.capabilities || !Array.isArray(DMSService.capabilities)) {
            wlrOutputAvailable = false;
            return;
        }

        const hasWlrOutput = DMSService.capabilities.includes("wlroutput");
        if (hasWlrOutput && !wlrOutputAvailable) {
            wlrOutputAvailable = true;
            log.info("wlr-output-management capability detected");
            requestState();
            return;
        }

        if (!hasWlrOutput) {
            wlrOutputAvailable = false;
        }
    }

    function requestState() {
        if (!DMSService.isConnected || !wlrOutputAvailable) {
            return;
        }

        DMSService.sendRequest("wlroutput.getState", null, response => {
            if (!response.result) {
                return;
            }
            handleStateUpdate(response.result);
        });
    }

    function handleStateUpdate(state) {
        outputs = state.outputs || [];
        serial = state.serial || 0;

        if (outputs.length === 0) {
            log.warn("Received empty outputs list");
        } else {
            log.debug("Updated with", outputs.length, "outputs, serial:", serial);
            outputs.forEach((output, index) => {
                log.debug("Output", index, "-", output.name, "enabled:", output.enabled, "mode:", output.currentMode ? output.currentMode.width + "x" + output.currentMode.height + "@" + (output.currentMode.refresh / 1000) + "Hz" : "none");
            });
        }
        stateChanged();
    }

    function getOutput(name) {
        for (const output of outputs) {
            if (output.name === name) {
                return output;
            }
        }
        return null;
    }

    function applyConfiguration(heads, callback) {
        if (!DMSService.isConnected || !wlrOutputAvailable) {
            if (callback) {
                callback(false, I18n.tr("Not connected"));
            }
            return;
        }

        log.debug("Applying configuration for", heads.length, "outputs");
        heads.forEach((head, index) => {
            log.debug("Head", index, "- name:", head.name, "enabled:", head.enabled, "modeId:", head.modeId, "customMode:", JSON.stringify(head.customMode), "position:", JSON.stringify(head.position), "scale:", head.scale, "transform:", head.transform, "adaptiveSync:", head.adaptiveSync);
        });

        DMSService.sendRequest("wlroutput.applyConfiguration", {
            "heads": heads
        }, response => {
            const success = !response.error && response.result?.success === true;
            const message = response.error || response.result?.message || "";

            if (!success) {
                log.warn("applyConfiguration error:", message);
            } else {
                log.debug("Configuration applied successfully");
            }

            configurationApplied(success, message);
            if (callback) {
                callback(success, message);
            }
        }, 5000);
    }

    function testConfiguration(heads, callback) {
        if (!DMSService.isConnected || !wlrOutputAvailable) {
            if (callback) {
                callback(false, I18n.tr("Not connected"));
            }
            return;
        }

        log.debug("Testing configuration for", heads.length, "outputs");

        DMSService.sendRequest("wlroutput.testConfiguration", {
            "heads": heads
        }, response => {
            const success = !response.error && response.result?.success === true;
            const message = response.error || response.result?.message || "";

            if (!success) {
                log.warn("testConfiguration error:", message);
            } else {
                log.debug("Configuration test passed");
            }

            if (callback) {
                callback(success, message);
            }
        }, 5000);
    }

    function applyOutputsConfig(outputsData, connectedOutputs, callback) {
        if (!wlrOutputAvailable) {
            if (callback)
                callback(false, I18n.tr("Not connected"));
            return;
        }
        const heads = outputsConfigHeads(outputsData, connectedOutputs);
        if (heads.length === 0) {
            if (callback)
                callback(false, I18n.tr("No monitors"));
            return;
        }
        applyConfiguration(heads, callback);
    }

    function outputsConfigHeads(outputsData, connectedOutputs) {
        const heads = [];
        for (const name in outputsData) {
            if (!connectedOutputs[name])
                continue;
            const output = outputsData[name];
            const mode = (output.modes && output.current_mode >= 0) ? output.modes[output.current_mode] : null;
            const enabled = !!mode;
            const head = {
                "name": name,
                "enabled": enabled
            };

            if (enabled) {
                if (mode.id !== undefined)
                    head.modeId = mode.id;
                else
                    head.customMode = {
                        "width": mode.width,
                        "height": mode.height,
                        "refresh": mode.refresh_rate
                    };

                if (output.logical) {
                    head.position = {
                        "x": output.logical.x ?? 0,
                        "y": output.logical.y ?? 0
                    };
                    head.scale = output.logical.scale ?? 1.0;
                    head.transform = OutputModel.transformIndex(output.logical.transform);
                }

                // Only heads that reported adaptive sync (wlr-output-management v4) accept set_adaptive_sync.
                if (output.vrr_supported)
                    head.adaptiveSync = output.vrr_enabled ? 1 : 0;
            }
            heads.push(head);
        }

        return heads;
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            log.info("Session resumed, re-requesting output state, current outputs:", outputs.length);
            requestState();
        }
    }
}
