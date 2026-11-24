import QtQuick
import QtTest
import "../../Services/OutputCycleState.js" as OutputCycleState

TestCase {
    name: "OutputCycleState"

    function output(id, enabled) {
        return {
            id: id,
            enabled: enabled
        };
    }

    function test_disabledTargetStartsPendingCycle() {
        const result = OutputCycleState.requestCycle(OutputCycleState.emptyState(), [output("HDMI-A-1", false), output("eDP-1", true)], "eDP-1");

        compare(result.status, "accepted");
        compare(result.state.pending, "HDMI-A-1");
        compare(result.intents.length, 1);
        compare(result.intents[0].id, "HDMI-A-1");
        verify(result.intents[0].enabled);
    }

    function test_confirmedTargetDisablesEveryOtherEnabledOutput() {
        const state = {
            ring: ["HDMI-A-1", "eDP-1", "DP-1"],
            selected: "eDP-1",
            pending: "HDMI-A-1"
        };
        const result = OutputCycleState.handleOutputsChanged(state, [output("DP-1", true), output("HDMI-A-1", true), output("eDP-1", true)]);

        compare(result.state.pending, "");
        compare(result.state.selected, "HDMI-A-1");
        compare(result.intents.length, 2);
        compare(result.intents[0].id, "DP-1");
        verify(!result.intents[0].enabled);
        compare(result.intents[1].id, "eDP-1");
        verify(!result.intents[1].enabled);
    }

    function test_alreadyEnabledTargetDisablesPeersImmediately() {
        const result = OutputCycleState.requestCycle(OutputCycleState.emptyState(), [output("DP-1", true), output("eDP-1", true)], "DP-1");

        compare(result.status, "accepted");
        compare(result.state.selected, "eDP-1");
        compare(result.intents.length, 1);
        compare(result.intents[0].id, "DP-1");
        verify(!result.intents[0].enabled);
    }

    function test_emptyMapRetainsPendingCycleUntilTargetConfirms() {
        const state = {
            ring: ["HDMI-A-1", "eDP-1"],
            selected: "eDP-1",
            pending: "HDMI-A-1"
        };
        const empty = OutputCycleState.handleOutputsChanged(state, []);

        compare(empty.state.ring, state.ring);
        compare(empty.state.selected, "eDP-1");
        compare(empty.state.pending, "HDMI-A-1");
        compare(empty.intents.length, 0);

        const confirmed = OutputCycleState.handleOutputsChanged(empty.state, [output("HDMI-A-1", true), output("eDP-1", true)]);

        compare(confirmed.state.pending, "");
        compare(confirmed.state.selected, "HDMI-A-1");
        compare(confirmed.intents.length, 1);
        compare(confirmed.intents[0].id, "eDP-1");
        verify(!confirmed.intents[0].enabled);
    }

    function test_unplugPreservesAllEnabledOutputs() {
        const state = {
            ring: ["DP-1", "HDMI-A-1", "eDP-1"],
            selected: "HDMI-A-1",
            pending: ""
        };
        const result = OutputCycleState.handleOutputsChanged(state, [output("DP-1", true), output("eDP-1", true)]);

        compare(result.state.pending, "");
        compare(result.intents, []);
    }

    function test_disabledFallbackOnlyEnablesPreviousOutput() {
        const state = {
            ring: ["DP-1", "HDMI-A-1", "eDP-1"],
            selected: "HDMI-A-1",
            pending: "",
            original: {
                "DP-1": true,
                "eDP-1": true
            }
        };
        const result = OutputCycleState.handleOutputsChanged(state, [output("DP-1", false), output("eDP-1", false)]);

        compare(result.state.pending, "");
        compare(result.state.selected, "DP-1");
        compare(result.intents.length, 1);
        compare(result.intents[0].id, "DP-1");
        verify(result.intents[0].enabled);
    }

    function test_unplugWithoutCyclePreservesWorkingDisplay() {
        let state = OutputCycleState.handleOutputsChanged(OutputCycleState.emptyState(), [output("DP-1", true), output("DP-2", false), output("eDP-1", false)]).state;
        state = OutputCycleState.handleOutputsChanged(state, [output("DP-1", true), output("DP-2", true), output("eDP-1", false)]).state;
        const unplugged = OutputCycleState.handleOutputsChanged(state, [output("DP-2", true), output("eDP-1", false)]);
        compare(unplugged.intents, []);
        compare(unplugged.state.pending, "");
        const repeated = OutputCycleState.handleOutputsChanged(unplugged.state, [output("DP-2", true), output("eDP-1", false)]);
        compare(repeated.intents, []);
    }

    function test_fallbackConfirmationDoesNotDisableNewlyEnabledPeer() {
        const heads = [output("DP-1", true), output("DP-2", false), output("eDP-1", false)];
        const initial = OutputCycleState.handleOutputsChanged(OutputCycleState.emptyState(), heads).state;

        const cycle = OutputCycleState.requestCycle(initial, heads, "DP-1");
        compare(cycle.intents, [
            {
                id: "DP-2",
                enabled: true
            }
        ]);
        const cycled = OutputCycleState.handleOutputsChanged(cycle.state, [output("DP-1", true), output("DP-2", true), output("eDP-1", false)]);
        compare(cycled.intents, [
            {
                id: "DP-1",
                enabled: false
            }
        ]);

        const unplugged = OutputCycleState.handleOutputsChanged(cycled.state, [output("DP-1", false), output("eDP-1", false)]);
        compare(unplugged.intents, [
            {
                id: "DP-1",
                enabled: true
            }
        ]);
        const confirmed = OutputCycleState.handleOutputsChanged(unplugged.state, [output("DP-1", true), output("eDP-1", false)]);
        compare(confirmed.intents, []);
        compare(confirmed.state.pending, "");
        compare(confirmed.state.original, {
            "DP-2": false
        });
    }

    function test_unplugWithoutCycleLeavesDisabledOutputAlone() {
        const state = OutputCycleState.handleOutputsChanged(OutputCycleState.emptyState(), [output("DP-2", true), output("HDMI-A-2", false)]).state;
        const asleep = OutputCycleState.handleOutputsChanged(state, [output("HDMI-A-2", false)]);
        compare(asleep.intents, []);
        const awake = OutputCycleState.handleOutputsChanged(asleep.state, [output("DP-2", true), output("HDMI-A-2", false)]);
        compare(awake.intents, []);
    }

    function test_cycleRoundTripForgetsOutputDmsEnabled() {
        let state = OutputCycleState.handleOutputsChanged(OutputCycleState.emptyState(), [output("DP-2", true), output("HDMI-A-2", false)]).state;
        state = OutputCycleState.requestCycle(state, [output("DP-2", true), output("HDMI-A-2", false)], "DP-2").state;
        state = OutputCycleState.handleOutputsChanged(state, [output("DP-2", true), output("HDMI-A-2", true)]).state;
        state = OutputCycleState.handleOutputsChanged(state, [output("DP-2", false), output("HDMI-A-2", true)]).state;
        state = OutputCycleState.requestCycle(state, [output("DP-2", false), output("HDMI-A-2", true)], "HDMI-A-2").state;
        state = OutputCycleState.handleOutputsChanged(state, [output("DP-2", true), output("HDMI-A-2", true)]).state;
        state = OutputCycleState.handleOutputsChanged(state, [output("DP-2", true), output("HDMI-A-2", false)]).state;
        compare(state.original, {});

        const asleep = OutputCycleState.handleOutputsChanged(state, [output("HDMI-A-2", false)]);
        compare(asleep.intents, []);
    }

    function test_missingPendingTargetCancelsWithoutIntent() {
        const state = {
            ring: ["HDMI-A-1", "eDP-1"],
            selected: "eDP-1",
            pending: "HDMI-A-1"
        };
        const result = OutputCycleState.handleOutputsChanged(state, [output("eDP-1", true)]);

        compare(result.state.pending, "");
        compare(result.intents.length, 0);
    }

    function test_pendingCycleIsBusy() {
        const state = {
            ring: ["HDMI-A-1", "eDP-1"],
            selected: "eDP-1",
            pending: "HDMI-A-1"
        };
        const result = OutputCycleState.requestCycle(state, [output("HDMI-A-1", false), output("eDP-1", true)], "eDP-1");

        compare(result.status, "busy");
        compare(result.intents.length, 0);
    }

    function test_singleOutputIsNoop() {
        const state = OutputCycleState.emptyState();
        const result = OutputCycleState.requestCycle(state, [output("eDP-1", true)], "eDP-1");

        compare(result.status, "no-op");
        compare(result.intents.length, 0);
    }
}
