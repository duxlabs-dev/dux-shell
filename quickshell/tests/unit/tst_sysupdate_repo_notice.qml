import QtQuick
import QtTest
import "../../Services/RepoMoveNotice.js" as RepoMoveNotice

TestCase {
    name: "SysupdateRepoNotice"

    readonly property var legacy: ["/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:danklinux.repo"]

    function test_repoNoticeDue_data() {
        return [
            { tag: "legacy on a new version", legacy: legacy, seen: "", current: "1.4.0", due: true },
            { tag: "release re-arms", legacy: legacy, seen: "1.4.0", current: "1.4.1", due: true },
            { tag: "already shown for this version", legacy: legacy, seen: "1.4.1", current: "1.4.1", due: false },
            { tag: "nothing to migrate", legacy: [], seen: "", current: "1.4.0", due: false },
            { tag: "version not read yet", legacy: legacy, seen: "1.4.0", current: "", due: false }
        ];
    }

    function test_repoNoticeDue(row) {
        compare(RepoMoveNotice.repoNoticeDue(row.legacy, row.seen, row.current), row.due);
    }

}
