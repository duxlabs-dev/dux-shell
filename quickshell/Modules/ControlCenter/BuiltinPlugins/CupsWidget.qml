import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    Ref {
        service: CupsService
    }

    ccWidgetIsToggle: false
    ccWidgetIcon: "print"
    ccWidgetPrimaryText: I18n.tr("Printers")
    ccWidgetSecondaryText: {
        if (!CupsService.cupsAvailable)
            return I18n.tr("Print Server not available");
        if (CupsService.getPrintersNum() === 0)
            return I18n.tr("No printer found", "empty state in printer list");
        return I18n.tr("Printers") + ": " + CupsService.getPrintersNum() + " - " + I18n.tr("Jobs") + ": " + CupsService.getTotalJobsNum();
    }
    ccWidgetIsActive: CupsService.cupsAvailable && CupsService.getTotalJobsNum() > 0

    onCcWidgetToggled: {}

    ccDetailContent: Component {
        Item {
            id: detailRoot

            readonly property string title: I18n.tr("Printers")
            readonly property bool hasPrinters: CupsService.cupsAvailable && CupsService.getPrintersNum() > 0
            readonly property var jobs: CupsService.getCurrentPrinterJobs()
            readonly property bool printerStopped: CupsService.getCurrentPrinterState() === "stopped"

            readonly property Item headerActions: CcSettingsButton {
                settingsTab: "printers"
            }

            DFlickable {
                anchors.fill: parent
                contentHeight: detailColumn.height
                clip: true

                Column {
                    id: detailColumn
                    width: parent.width
                    spacing: CcMetrics.detailContentGap

                    CcEmptyState {
                        visible: !detailRoot.hasPrinters
                        iconName: "print_disabled"
                        title: CupsService.cupsAvailable ? I18n.tr("No printer found", "empty state in printer list") : I18n.tr("Print Server not available")
                    }

                    CcGroup {
                        visible: detailRoot.hasPrinters

                        CcListRow {
                            iconName: "print"
                            title: I18n.tr("Printers")
                            subtitle: CupsService.getCurrentPrinterStatePrettyShort()

                            DDropdown {
                                anchors.verticalCenter: parent.verticalCenter
                                compactMode: true
                                dropdownWidth: CcMetrics.rowDropdownWidth
                                alignPopupRight: true
                                currentValue: CupsService.getSelectedPrinter()
                                options: CupsService.getPrintersNames()
                                onValueChanged: value => CupsService.setSelectedPrinter(value)
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingS

                            DButton {
                                buttonHeight: Theme.buttonHeightXS
                                iconName: detailRoot.printerStopped ? "play_arrow" : "pause"
                                iconSize: Theme.iconSizeSmall
                                text: detailRoot.printerStopped ? I18n.tr("Resume") : I18n.tr("Pause")
                                backgroundColor: Theme.chipSurface
                                textColor: Theme.surfaceText
                                onClicked: {
                                    const selected = CupsService.getSelectedPrinter();
                                    if (detailRoot.printerStopped)
                                        CupsService.resumePrinter(selected);
                                    else
                                        CupsService.pausePrinter(selected);
                                }
                            }

                            DButton {
                                buttonHeight: Theme.buttonHeightXS
                                iconName: "delete_forever"
                                iconSize: Theme.iconSizeSmall
                                text: I18n.tr("Jobs")
                                backgroundColor: Theme.errorHover
                                textColor: Theme.error
                                onClicked: CupsService.purgeJobs(CupsService.getSelectedPrinter())
                            }
                        }
                    }

                    CcSectionLabel {
                        text: I18n.tr("Jobs")
                        visible: detailRoot.hasPrinters
                    }

                    CcEmptyState {
                        visible: detailRoot.hasPrinters && detailRoot.jobs.length === 0
                        iconName: "work"
                        title: I18n.tr("The job queue of this printer is empty")
                    }

                    CcGroup {
                        visible: detailRoot.hasPrinters && detailRoot.jobs.length > 0

                        Repeater {
                            model: detailRoot.jobs

                            CcListRow {
                                id: jobRow

                                required property var modelData

                                iconName: "docs"
                                title: "#" + modelData.id + " • " + modelData.state
                                subtitle: new Date(modelData.timeCreated).toLocaleString(Qt.locale(), Locale.ShortFormat) + " • " + I18n.tr("%1 KB", "print job size in kilobytes").arg(Math.round(modelData.size / 1024))

                                DActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    buttonSize: Theme.buttonHeightXS
                                    iconSize: Theme.iconSizeMedium
                                    iconName: "delete"
                                    Accessible.name: I18n.tr("Cancel")
                                    iconColor: Theme.error
                                    onClicked: CupsService.cancelJob(CupsService.getSelectedPrinter(), jobRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ccExpandedContent: Component {
        CcTileActions {
            actions: CupsService.getPrintersNames().map(name => ({
                        text: name,
                        icon: "print",
                        active: name === CupsService.getSelectedPrinter(),
                        trigger: () => CupsService.setSelectedPrinter(name)
                    }))
        }
    }
}
