import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets

DModal {
    id: root

    layerNamespace: "dms:icc-profile-info"
    keepPopoutsOpen: true

    property string outputName: ""
    readonly property var profile: outputName !== "" ? (ICCService.status[outputName] ?? null) : null

    function showProfile(output) {
        outputName = output;
        open();
    }

    function toneCurveText(p) {
        if (!p)
            return "";

        const kind = p.trcKind;
        if (kind === "gamma")
            return I18n.tr("Gamma %1", "%1 is a gamma value").arg((p.trcGamma ?? 0).toFixed(2));
        if (kind === "table")
            return I18n.tr("Table", "Tone curve stored as a lookup table") + " · " + p.trcEntries;
        if (kind === "identity")
            return I18n.tr("Identity", "Tone curve that leaves the signal unchanged");
        if (kind === "mixed")
            return I18n.tr("Mixed", "Tone curves that differ between channels");
        return "";
    }

    function whitePointText(p) {
        if (!p)
            return "";
        if (p.whitePointName && p.whitePointCCT)
            return p.whitePointName + " · " + p.whitePointCCT + "K";
        if (p.whitePointCCT)
            return p.whitePointCCT + "K";
        if (p.whitePointX !== undefined)
            return p.whitePointX.toFixed(4) + ", " + p.whitePointY.toFixed(4);
        return "";
    }

    function vcgtText(p) {
        if (!p)
            return "";
        return p.hasVCGT ? (p.vcgtChannels + " × " + p.vcgtEntries) : I18n.tr("No", "No");
    }

    function sizeText(p) {
        if (!p || !p.size)
            return "";
        return p.size < 1024 ? p.size + " B" : (p.size / 1024).toFixed(1) + " KB";
    }

    function modifiedText(p) {
        if (!p || !p.modified)
            return "";
        return Qt.formatDateTime(new Date(p.modified * 1000), "yyyy-MM-dd HH:mm");
    }

    readonly property var details: {
        const p = profile;
        if (!p)
            return [];

        return [
            {
                "label": I18n.tr("Version", "Version"),
                "value": p.version || ""
            },
            {
                "label": I18n.tr("Class", "ICC profile class, e.g. monitor, scanner, printer"),
                "value": p.class || ""
            },
            {
                "label": I18n.tr("Color space", "ICC profile color space"),
                "value": p.colorSpace || ""
            },
            {
                "label": I18n.tr("Tone curve", "How the ICC profile stores its tone reproduction curves"),
                "value": toneCurveText(p)
            },
            {
                "label": I18n.tr("Video card gamma table", "Video card gamma table (vcgt) carried by the profile"),
                "value": vcgtText(p)
            },
            {
                "label": I18n.tr("White point", "White point the ICC profile was produced for"),
                "value": whitePointText(p)
            },
            {
                "label": I18n.tr("Active", "Active"),
                "value": p.active ? I18n.tr("Yes", "Yes") : I18n.tr("No", "No")
            },
            {
                "label": I18n.tr("Size", "Size"),
                "value": sizeText(p)
            },
            {
                "label": I18n.tr("Modified", "Modified"),
                "value": modifiedText(p)
            }
        ];
    }

    modalWidth: 580
    modalHeight: 520
    onBackgroundClicked: close()
    onVisibleChanged: {
        if (!visible)
            outputName = "";
    }

    content: Component {
        Item {
            anchors.fill: parent

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Row {
                    width: parent.width

                    Column {
                        width: parent.width - 40
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.profile?.description || I18n.tr("Color Profile", "Display Config output card label for the per-monitor ICC profile row")
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                            font.weight: Font.Medium
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: root.outputName
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceTextMedium
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    DActionButton {
                        iconName: "close"
                        iconSize: Theme.iconSize - 4
                        iconColor: Theme.surfaceText
                        onClicked: root.close()
                    }
                }

                StyledRect {
                    width: parent.width
                    height: parent.height - 120
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowNestedSurface
                    border.color: Theme.outlineMedium
                    border.width: Theme.layerOutlineWidth
                    clip: true

                    DFlickable {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        contentHeight: detailColumn.implicitHeight

                        Column {
                            id: detailColumn

                            width: parent.width
                            spacing: Theme.spacingS

                            Repeater {
                                model: root.details

                                delegate: Column {
                                    required property var modelData

                                    width: detailColumn.width
                                    spacing: 2

                                    StyledText {
                                        text: modelData.label
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        width: parent.width
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        text: modelData.value !== "" ? modelData.value : "—"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        width: parent.width
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }

                            StyledText {
                                visible: root.details.length === 0
                                text: I18n.tr("No information available", "No information available")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceTextMedium
                            }

                            StyledText {
                                text: I18n.tr("Path", "Path")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                width: parent.width
                                topPadding: Theme.spacingS
                            }

                            StyledText {
                                text: root.profile?.path || "—"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                                width: parent.width
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 40

                    DButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Close", "Close")
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
