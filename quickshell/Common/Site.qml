pragma Singleton

import Quickshell

Singleton {
    readonly property string domain: "duxlabs.dev"
    readonly property string web: "https://" + domain
    readonly property string docs: web + "/docs"
    readonly property string api: "https://api.duxlabs.dev"
    readonly property string plugins: "https://plugins." + domain
    readonly property string wallpaperCreator: "https://wallpaper." + domain
}
