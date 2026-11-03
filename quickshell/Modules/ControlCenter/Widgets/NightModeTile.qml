import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

CcTile {
    id: root

    iconName: NightModeService.nightModeEnabled ? "nightlight" : "dark_mode"
    title: I18n.tr("Night mode")
    active: NightModeService.nightModeEnabled || false
    available: NightModeService.automationAvailable

    onClicked: NightModeService.toggleNightMode()
    expandedContent: Component {
        Column {
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: I18n.tr("Color Temperature", "Color Temperature")
                color: root.contentColor
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
            }

            DSlider {
                width: parent.width
                minimum: 1000
                maximum: 6000
                step: 100
                unit: "K"
                Accessible.name: I18n.tr("Color Temperature", "Color Temperature")
                value: SessionData.nightModeTemperature
                onSliderValueChanged: newValue => {
                    SessionData.setNightModeTemperature(newValue);
                    if (SessionData.nightModeHighTemperature < newValue)
                        SessionData.setNightModeHighTemperature(newValue);
                }
            }
        }
    }
}
