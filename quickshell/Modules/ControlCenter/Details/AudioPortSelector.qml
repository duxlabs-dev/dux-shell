pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Widgets
import qs.Services

CcSheetDialog {
    id: root

    property var node: null
    property bool isLoading: false

    readonly property bool nodeValid: node !== null && node.isSink
    readonly property var choices: nodeValid ? (AudioService.outputChoices[node.name] ?? []) : []

    iconName: node ? AudioService.sinkIcon(node) : "speaker"
    title: node ? AudioService.displayName(node) : ""
    subtitle: I18n.tr("Port Selection", "audio port selector modal subtitle")
    statusText: {
        if (isLoading)
            return I18n.tr("Loading ports...", "audio port selector loading state");
        if (choices.length === 0)
            return I18n.tr("No ports found", "audio port selector empty state");
        return I18n.tr("Current: %1", "audio port selector active port label, %1 is the port name").arg(choices.find(c => c.active)?.title ?? "");
    }
    statusColor: isLoading ? Theme.primary : Theme.surfaceVariantText

    function show(sinkNode) {
        if (!sinkNode || !sinkNode.isSink)
            return;
        node = sinkNode;
        isLoading = true;
        AudioService.refreshCards();
        AudioService.refreshSinkPorts(() => {
            root.isLoading = false;
        });
        present();
    }

    function select(choice) {
        if (!nodeValid || isLoading || choice.availability === "no")
            return;
        isLoading = true;
        AudioService.activateOutputChoice(choice, (success, message) => {
            root.isLoading = false;
            ToastService.showToast(message, success ? ToastService.levelInfo : ToastService.levelError);
            if (success)
                root.dismiss();
        });
    }

    onNodeValidChanged: {
        if (shown && !nodeValid)
            dismiss();
    }

    onDismissed: node = null

    CcGroup {
        visible: root.choices.length > 0

        Repeater {
            model: root.choices

            CcListRow {
                required property var modelData

                readonly property bool unavailable: modelData.availability === "no"

                title: modelData.title
                subtitle: {
                    if (unavailable)
                        return I18n.tr("Unavailable", "audio port availability status");
                    if (modelData.availability === "yes")
                        return I18n.tr("Available", "audio port availability status");
                    return "";
                }
                active: modelData.active
                enabled: !unavailable && !root.isLoading
                clickable: !active
                onClicked: root.select(modelData)
            }
        }
    }
}
