pragma Singleton
import QtQuick

QtObject {
    property bool preparingForSleep: false
    property bool sleepRequested: false
    signal sessionResumed
    signal lidOpened
}
