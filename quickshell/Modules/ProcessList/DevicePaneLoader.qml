pragma ComponentBehavior: Bound

import QtQuick
import qs.Services

Loader {
    id: root

    property string key: "cpu"
    property string variant: "window"

    readonly property var parsed: SysmonService.parseKey(key)
    readonly property string iconName: SysmonService.device(key)?.icon ?? ""

    sourceComponent: {
        switch (parsed.type) {
        case "memory":
            return memoryPane;
        case "gpu":
            return gpuPane;
        case "disk":
            return parsed.id ? diskPane : aggregatePane;
        case "net":
            return parsed.id ? netPane : aggregatePane;
        }
        return cpuPane;
    }

    Component {
        id: cpuPane
        CpuPane {
            variant: root.variant
            iconName: root.iconName
        }
    }

    Component {
        id: memoryPane
        MemoryPane {
            variant: root.variant
            iconName: root.iconName
        }
    }

    Component {
        id: gpuPane
        GpuPane {
            variant: root.variant
            iconName: root.iconName
            slot: root.parsed.id
        }
    }

    Component {
        id: diskPane
        DiskPane {
            variant: root.variant
            iconName: root.iconName
            deviceName: root.parsed.id
        }
    }

    Component {
        id: netPane
        NetworkPane {
            variant: root.variant
            iconName: root.iconName
            deviceName: root.parsed.id
            title: SysmonService.device(root.key)?.name ?? root.parsed.id
        }
    }

    Component {
        id: aggregatePane
        AggregatePane {
            variant: root.variant
            iconName: root.iconName
            type: root.parsed.type
        }
    }
}
