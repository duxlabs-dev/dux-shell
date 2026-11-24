import QtQuick
import Quickshell.Services.Pipewire
import qs.Common

Item {
    id: root
    visible: false

    readonly property bool ready: Pipewire.ready
    readonly property var nodes: Pipewire.nodes.values
    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property var defaultSource: Pipewire.defaultAudioSource

    signal nodesUpdated

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    function isVideoSource(node) {
        return !!node && (node.type & PwNodeType.VideoSource) === PwNodeType.VideoSource;
    }

    function channelSide(channel) {
        switch (channel) {
        case PwAudioChannel.FrontLeft:
        case PwAudioChannel.FrontLeftCenter:
        case PwAudioChannel.FrontLeftWide:
        case PwAudioChannel.FrontLeftHigh:
        case PwAudioChannel.LowFrequencyEffectsLeft:
        case PwAudioChannel.SideLeft:
        case PwAudioChannel.RearLeft:
        case PwAudioChannel.RearLeftCenter:
        case PwAudioChannel.TopFrontLeft:
        case PwAudioChannel.TopFrontLeftCenter:
        case PwAudioChannel.TopSideLeft:
        case PwAudioChannel.TopRearLeft:
        case PwAudioChannel.BottomLeftCenter:
            return "left";
        case PwAudioChannel.FrontRight:
        case PwAudioChannel.FrontRightCenter:
        case PwAudioChannel.FrontRightWide:
        case PwAudioChannel.FrontRightHigh:
        case PwAudioChannel.LowFrequencyEffectsRight:
        case PwAudioChannel.SideRight:
        case PwAudioChannel.RearRight:
        case PwAudioChannel.RearRightCenter:
        case PwAudioChannel.TopFrontRight:
        case PwAudioChannel.TopFrontRightCenter:
        case PwAudioChannel.TopSideRight:
        case PwAudioChannel.TopRearRight:
        case PwAudioChannel.BottomRightCenter:
            return "right";
        default:
            return "center";
        }
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            root.nodesUpdated();
        }
    }

	PwObjectTracker {
		objects: Pipewire.nodes.values.filter(node =>
			node.audio || !node.isStream
		)
	}
}
