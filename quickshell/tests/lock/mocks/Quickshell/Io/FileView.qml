import QtQuick

Item {
    property string path
    property bool printErrors
    property bool watchChanges
    readonly property bool loaded: path !== "" && !MockFiles.missing.includes(path)
    function reload() {
    }
}
