import QtQuick
import qs.Common
import "Drives.js" as Drives

QtObject {
    property string level: ""
    readonly property string text: {
        switch (Drives.healthWord(level)) {
        case "ok": return I18n.tr("Healthy", "drive health");
        case "warning": return I18n.tr("Warning");
        case "critical": return I18n.tr("Critical", "drive health");
        }
        return "";
    }
}
