import QtQuick
import qs.Common
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:plugins:" + layerNamespacePlugin

    property string pluginId: ""
    property var triggerScreen: null
    property Component pluginContent: null
    property real contentWidth: 400
    property real contentHeight: 0

    popupWidth: contentWidth
    popupHeight: contentHeight
    screen: triggerScreen
    shouldBeVisible: false

    onBackgroundClicked: close()

    content: Component {
        Rectangle {
            id: popoutContainer

            implicitHeight: popoutColumn.implicitHeight + PopoutMetrics.contentPadding * 2
            color: "transparent"
            focus: true

            readonly property bool rootShouldBeVisible: root.shouldBeVisible

            Component.onCompleted: {
                if (root.shouldBeVisible) {
                    forceActiveFocus();
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }

            onRootShouldBeVisibleChanged: {
                if (rootShouldBeVisible) {
                    Qt.callLater(() => {
                        popoutContainer.forceActiveFocus();
                    });
                }
            }

            Column {
                id: popoutColumn
                width: parent.width - PopoutMetrics.contentPadding * 2
                x: PopoutMetrics.contentPadding
                y: PopoutMetrics.contentPadding
                spacing: Theme.spacingS

                Loader {
                    id: popoutContentLoader
                    property string pluginId: root.pluginId
                    width: parent.width
                    sourceComponent: root.pluginContent

                    onLoaded: {
                        if (item && "closePopout" in item) {
                            item.closePopout = function () {
                                root.close();
                            };
                        }
                        if (item && "parentPopout" in item) {
                            item.parentPopout = root;
                        }
                        if (item) {
                            root.contentHeight = Qt.binding(() => item.implicitHeight + PopoutMetrics.contentPadding * 2);
                        }
                    }
                }
            }
        }
    }
}
