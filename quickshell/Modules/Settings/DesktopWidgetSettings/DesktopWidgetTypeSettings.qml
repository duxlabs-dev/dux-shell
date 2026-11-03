import QtQuick
import qs.Modules.Settings.LockWidgetSettings as LWS

Loader {
    id: root

    property string instanceId: ""
    property var instanceData: null
    property var widgetDef: null
    property var parentModal: null
    readonly property string widgetType: instanceData?.widgetType ?? ""

    active: instanceData !== null
    sourceComponent: {
        switch (widgetType) {
        case "desktopClock":
            return clockSettings;
        case "systemMonitor":
            return systemMonitorSettings;
        case "lockAuth":
            return lockAuthSettings;
        case "lockNotifications":
            return lockNotificationsSettings;
        case "lockStatus":
            return lockStatusSettings;
        case "lockDate":
            return lockDateSettings;
        case "lockPower":
            return lockPowerSettings;
        case "greeterSession":
            return null;
        default:
            return pluginSettings;
        }
    }

    Component {
        id: clockSettings

        ClockSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
        }
    }

    Component {
        id: systemMonitorSettings

        SystemMonitorSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
        }
    }

    Component {
        id: lockAuthSettings

        LWS.LockAuthSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
        }
    }

    Component {
        id: lockNotificationsSettings

        LWS.LockNotificationsSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
        }
    }

    Component {
        id: lockStatusSettings

        LWS.LockStatusSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
            parentModal: root.parentModal
        }
    }

    Component {
        id: lockDateSettings

        LWS.LockDateSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
        }
    }

    Component {
        id: lockPowerSettings

        LWS.LockPowerSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
        }
    }

    Component {
        id: pluginSettings

        PluginDesktopWidgetSettings {
            instanceId: root.instanceId
            instanceData: root.instanceData
            widgetType: root.widgetType
            widgetDef: root.widgetDef
        }
    }
}
