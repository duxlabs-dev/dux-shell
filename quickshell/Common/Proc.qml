pragma Singleton

import Quickshell
import qs.DCommon.Common as DCommon

Singleton {
    readonly property int noTimeout: DCommon.Proc.noTimeout
    readonly property string dmsBin: DCommon.Proc.dmsBin

    function runCommand(id, command, callback, debounceMs, timeoutMs, owner) {
        DCommon.Proc.runCommand(id, command, callback, debounceMs, timeoutMs, owner);
    }

    function release(id) {
        DCommon.Proc.release(id);
    }
}
