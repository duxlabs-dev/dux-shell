import QtQuick
import "OutputCycleState.js" as OutputCycleState

QtObject {
    id: root

    required property QtObject wlrOutputService
    required property QtObject socket
    required property bool isNiri
    required property string currentOutput

    property var _outputCycleState: OutputCycleState.emptyState()

    Component.onCompleted: resolveOutputCycle()
    onIsNiriChanged: resolveOutputCycle()

    readonly property Connections outputConnection: Connections {
        target: root.wlrOutputService
        enabled: root.isNiri

        function onStateChanged() {
            root.resolveOutputCycle();
        }
    }

    readonly property Connections socketConnection: Connections {
        target: root.socket
        enabled: root.isNiri

        function onConnectionStateChanged() {
            if (root.socket.linkUp)
                root.resolveOutputCycle();
        }
    }

    function outputDescriptors() {
        return wlrOutputService.outputs.filter(output => output.name).map(output => ({
                    id: output.name,
                    enabled: output.enabled
                }));
    }

    function sendOutputAction(outputName, action) {
        if (!isNiri || !socket.connected || !socket.linkUp || !wlrOutputService.wlrOutputAvailable || !wlrOutputService.getOutput(outputName))
            return false;
        socket.send({
            "Output": {
                "output": outputName,
                "action": action
            }
        });
        return true;
    }

    function sendOutputIntent(intent) {
        return sendOutputAction(intent.id, intent.enabled ? "On" : "Off");
    }

    function applyOutputCycleTransition(transition) {
        const enableIntent = transition.intents.find(intent => intent.enabled);
        if (enableIntent && !sendOutputIntent(enableIntent)) {
            _outputCycleState = OutputCycleState.clearPending(transition.state);
            return false;
        }

        _outputCycleState = transition.state;
        for (const intent of transition.intents) {
            if (intent !== enableIntent)
                sendOutputIntent(intent);
        }
        return true;
    }

    function cycleSingleOutput() {
        if (!isNiri || !socket.linkUp || !wlrOutputService.wlrOutputAvailable)
            return "OUTPUT_CYCLE_UNSUPPORTED";
        if (_outputCycleState.pending)
            return "OUTPUT_CYCLE_BUSY";

        const transition = OutputCycleState.requestCycle(_outputCycleState, outputDescriptors(), currentOutput);
        if (transition.status === "busy")
            return "OUTPUT_CYCLE_BUSY";
        if (transition.status === "no-op")
            return "OUTPUT_CYCLE_NOOP";

        const accepted = applyOutputCycleTransition(transition);
        return accepted ? "OUTPUT_CYCLE_ACCEPTED" : "OUTPUT_CYCLE_NOOP";
    }

    function resolveOutputCycle() {
        if (!isNiri || !socket.linkUp || !wlrOutputService.wlrOutputAvailable)
            return;
        applyOutputCycleTransition(OutputCycleState.handleOutputsChanged(_outputCycleState, outputDescriptors()));
    }
}
