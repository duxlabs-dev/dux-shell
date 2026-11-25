import QtQuick
import qs.Common
import qs.Services

CcTile {
    iconName: "airplanemode_active"
    title: I18n.tr("Airplane mode")
    active: DMSService.airplaneMode
    available: DMSService.rfkillAvailable

    onClicked: DMSService.toggleAirplaneMode(response => {
        if (response?.error)
            ToastService.showError(I18n.tr("Failed to toggle airplane mode"), response.error);
    })
}
