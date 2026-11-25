import QtQuick

ShaderEffect {
    id: root

    property string type: "fade"
    property var params: ({})
    property variant source1
    property variant source2
    property real progress: 0
    property real smoothness: 0.1
    property real fillMode: 0
    property vector4d fillColor: Qt.vector4d(0, 0, 0, 1)
    property real screenWidth: width
    property real screenHeight: height

    readonly property real imageWidth1: screenWidth
    readonly property real imageHeight1: screenHeight
    readonly property real imageWidth2: screenWidth
    readonly property real imageHeight2: screenHeight
    readonly property real aspectRatio: width / height
    readonly property real scrollX: 50
    readonly property real scrollY: 50

    readonly property real direction: params.direction ?? 0
    readonly property real centerX: params.centerX ?? 0.5
    readonly property real centerY: params.centerY ?? 0.5
    readonly property real stripeCount: params.stripeCount ?? 12
    readonly property real angle: params.angle ?? 0
    readonly property real seed: params.seed ?? 0

    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_" + type.replace(" ", "_") + ".frag.qsb")
}
