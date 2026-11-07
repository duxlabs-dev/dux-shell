pragma Singleton
import QtQuick

QtObject {
    id: root

    property var warnings: []
    function scoped(module) {
        return {
            debug() {},
            info() {},
            warn(...args) {
                root.warnings = root.warnings.concat([args.join(" ")]);
            },
            error() {}
        };
    }
}
