import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null

    spacing: Theme.spacingL

    SettingsCard {
        title: I18n.tr("Profile", "noun, user account settings card title, profile image")
        settingKey: "userProfile"
        tags: ["user", "account", "profile", "avatar", "image"]

        SettingsRow {
            title: UserInfoService.fullName || UserInfoService.username
            subtitle: UserInfoService.username
            settingKey: "profileImage"
            tags: ["user", "account", "profile", "avatar", "image"]

            leading: DCircularImage {
                width: SettingsMetrics.avatarSize
                ringWidth: Theme.avatarRingWidth
                ringColor: Theme.avatarRingColor
                height: width
                imageSource: PortalService.profileImage
                fallbackIcon: "material:person"
            }

            DActionButton {
                iconName: "edit"
                tooltipText: I18n.tr("Select Profile Image", "profile image file browser title")
                onClicked: root.parentModal?.openProfileBrowser()
            }

            DActionButton {
                iconName: "close"
                Accessible.name: I18n.tr("Clear")
                enabled: PortalService.profileImage !== ""
                onClicked: PortalService.setProfileImage("")
            }
        }

        SettingsDropdownRow {
            id: ringRow

            readonly property var rings: [
                {
                    "value": "none",
                    "label": I18n.tr("None")
                },
                {
                    "value": "outline",
                    "label": I18n.tr("Outline")
                },
                {
                    "value": "primary",
                    "label": I18n.tr("Primary")
                },
                {
                    "value": "secondary",
                    "label": I18n.tr("Secondary")
                },
                {
                    "value": "tertiary",
                    "label": I18n.tr("Tertiary")
                }
            ]

            settingKey: "avatarRing"
            tags: ["user", "account", "profile", "avatar", "ring", "border", "color"]
            text: I18n.tr("Avatar ring", "user accounts dropdown, colored ring around the profile picture")
            options: rings.map(ring => ring.label)
            optionColorMap: {
                const map = {};
                for (const ring of rings) {
                    if (ring.value === "none")
                        continue;
                    map[ring.label] = ring.value === "outline" ? Theme.surfaceVariant : Theme.roleColor(ring.value);
                }
                return map;
            }
            currentValue: rings.find(ring => ring.value === SettingsData.avatarRing)?.label ?? ""
            onValueChanged: value => {
                const ring = rings.find(ring => ring.label === value);
                if (ring)
                    SettingsData.set("avatarRing", ring.value);
            }
        }
    }
}
