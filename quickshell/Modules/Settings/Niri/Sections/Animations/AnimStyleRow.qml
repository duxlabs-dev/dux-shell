import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets
import "../../../../../Common/niri/anim.js" as Anim
import "../../../../../Common/niri/sections/animations.js" as Section

// Style is not stored: it is read from the 11 animations, and picking one rewrites them.
NiriRow {
    id: root

    readonly property var styles: ["snappy", "default", "bouncy"]
    readonly property string current: {
        const state = NiriPageService.state;
        return Anim.styleOf(name => Section.read(state, name));
    }

    function apply(style) {
        for (const name of Anim.names) {
            const target = Anim.preset(style, name);
            for (const field of Anim.fields) {
                const key = Section.prefix + name + "." + field;
                if (target[field] === NiriPageService.defaultOf(key)) {
                    if (NiriPageService.isModified(key))
                        NiriPageService.reset(key);
                } else if (NiriPageService.get(key) !== target[field]) {
                    NiriPageService.set(key, target[field]);
                }
            }
        }
    }

    icon: "auto_awesome"
    title: I18n.tr("Style", "niri page animation preset row")
    tip: I18n.tr("Sets all 11 animations at once", "niri page animation preset row tip")
    controlWidth: group.width

    DButtonGroup {
        id: group

        anchors.verticalCenter: parent.verticalCenter
        arrowKeysSelect: false
        model: [
            {
                "text": I18n.tr("Snappy", "niri page animation preset")
            },
            {
                "text": I18n.tr("niri default", "niri page animation preset")
            },
            {
                "text": I18n.tr("Bouncy", "niri page animation preset")
            }
        ]
        currentIndex: root.styles.indexOf(root.current)
        Accessible.name: root.title
        onSelectionChanged: (index, selected) => {
            if (!selected || index === currentIndex)
                return;
            root.apply(root.styles[index]);
        }
    }
}
