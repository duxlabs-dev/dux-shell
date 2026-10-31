pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root

    // Ending one of these takes the desktop down.
    readonly property var sessionNames: ["systemd", "(sd-pam)", "sd-pam", "dbus-broker", "dbus-broker-launch", "dbus-daemon"].concat(Object.keys(reloadCommands))
    readonly property var treeSkipNames: sessionNames.concat(["qs", "quickshell", "dms"])
    // Compositors can't restart in place; "restart" reloads their config. Empty entries have no reload command.
    readonly property var reloadCommands: ({
            "hyprland": [],
            "niri": ["niri", "msg", "action", "load-config-file"],
            "sway": ["swaymsg", "reload"],
            "scroll": ["scrollmsg", "reload"],
            "mango": [],
            "labwc": ["labwc", "--reconfigure"],
            "miracle-wm": [],
            "aqueous": [],
            "umbriel": [],
            "kwin_wayland": [],
            "gnome-shell": []
        })

    // Children first; a skipped child keeps its whole subtree.
    readonly property string treeScript: 'walk() ( for c in $(pgrep -P "$1"); do n=$(tr "[:upper:]" "[:lower:]" < /proc/$c/comm 2>/dev/null) || continue; case " $2 " in *" $n "*) continue ;; esac; walk "$c" "$2"; kill "$c" 2>/dev/null; done ); walk "$1" "$2"; kill "$1"'

    // $1 pid, $2 its systemd unit. Only a unit's main process restarts through systemd (apps share the compositor's
    // unit). Terminal programs exit 3. Anything else is relaunched with its command line, environment and directory.
    readonly property string restartScript: 'p=$1; u=$2; case "$u" in *.service) [ "$(systemctl --user show -p MainPID --value "$u" 2>/dev/null)" = "$p" ] && exec systemctl --user restart "$u" ;; esac; s=$(cat "/proc/$p/stat") || exit 1; set -- ${s##*) }; [ "$5" = 0 ] || exit 3; t=$(mktemp -d) || exit 1; trap "rm -r \\"$t\\"" EXIT; cp "/proc/$p/cmdline" "$t/cmd" && cp "/proc/$p/environ" "$t/env" && cwd=$(readlink "/proc/$p/cwd") || exit 1; kill "$p" || exit 1; i=0; while kill -0 "$p" 2>/dev/null; do i=$((i + 1)); [ "$i" -gt 100 ] && exit 1; sleep 0.1; done; cd "$cwd" 2>/dev/null || cd; run="setsid -f"; command -v systemd-run >/dev/null && run="$run systemd-run --user --scope --quiet --collect"; cat "$t/env" "$t/cmd" | xargs -0 $run env -i >/dev/null 2>&1'
    // Root's side of a restart, run through pkexec.
    readonly property string systemRestartScript: 'p=$1; u=$2; case "$u" in *.service) [ "$(systemctl show -p MainPID --value "$u" 2>/dev/null)" = "$p" ] && exec systemctl restart "$u" ;; esac; exit 4'

    function name(process) {
        return (process?.command ?? "").toLowerCase();
    }

    function isOwn(process) {
        return (process?.username ?? "") === UserInfoService.username;
    }

    function isDms(process) {
        return (process?.pid ?? 0) === Quickshell.processId || (name(process) === "dms" && isOwn(process));
    }

    function isSession(process) {
        return sessionNames.includes(name(process));
    }

    function isCritical(process) {
        return isSession(process) || isDms(process);
    }

    function isCompositor(process) {
        return ["hyprland", "mango"].includes(name(process)) || (reloadCommands[name(process)] ?? []).length > 0;
    }

    // PID 1 is never signalled; everything else can be, other users' processes after authentication.
    function canEnd(process) {
        return (process?.pid ?? 0) > 1;
    }

    // Whether a restart path exists; "reload" for compositors. Other users' processes only restart as a system service,
    // which is decided when it runs.
    function restartKind(process) {
        if (isDms(process))
            return "dms";
        if (isCompositor(process))
            return "reload";
        if (!canEnd(process))
            return "";
        if (name(process) === "systemd" && isOwn(process))
            return "reexec";
        if (isSession(process))
            return "";
        return isOwn(process) ? "relaunch" : "system";
    }

    function canRestart(process) {
        return restartKind(process) !== "";
    }

    function title(action, process) {
        switch (action) {
        case "force":
            return I18n.tr("Force quit", "process action: kill the process immediately (SIGKILL)");
        case "tree":
            return I18n.tr("End process tree", "process action: quit the process and every process it started");
        case "restart":
            return restartKind(process) === "reload" ? I18n.tr("Reload", "process action: reload a compositor's configuration") : I18n.tr("Restart", "process action: start the process again");
        }
        return I18n.tr("Quit", "process action: ask the process to exit (SIGTERM)");
    }

    function failed(process, detail) {
        ToastService.showError(I18n.tr("Failed to restart %1", "toast title, %1 is a process name").arg(process?.command ?? ""), detail ?? "");
    }

    function run(action, process) {
        const pid = String(process?.pid ?? 0);
        if (!canEnd(process))
            return;
        // Unlocked, the root helper ends other users' processes without another password prompt.
        if (!isOwn(process) && DgopService.unlocked && action !== "restart") {
            const params = {
                "pid": process.pid
            };
            if (action === "tree")
                params.skip = treeSkipNames;
            else if (action === "force")
                params.signal = "KILL";
            DgopService.request(action === "tree" ? "process.tree" : "process.signal", params, null);
            return;
        }
        const auth = isOwn(process) ? [] : ["pkexec"];
        switch (action) {
        case "quit":
            Quickshell.execDetached(auth.concat(["kill", pid]));
            break;
        case "force":
            Quickshell.execDetached(auth.concat(["kill", "-9", pid]));
            break;
        case "tree":
            Quickshell.execDetached(auth.concat(["sh", "-c", treeScript, "sh", pid, treeSkipNames.join(" ")]));
            break;
        case "restart":
            restart(process);
            break;
        }
    }

    function restart(process) {
        const pid = String(process.pid);
        switch (restartKind(process)) {
        case "dms":
            Quickshell.execDetached([Proc.dmsBin, "restart"]);
            return;
        case "reload":
            if (name(process) === "hyprland")
                HyprlandService.reloadConfig();
            else if (name(process) === "mango")
                MangoService.reloadConfig(true);
            else
                Quickshell.execDetached(reloadCommands[name(process)]);
            return;
        case "reexec":
            Quickshell.execDetached(["systemctl", "--user", "daemon-reexec"]);
            return;
        case "relaunch":
            DgopService.fetchProcessDetail(process.pid, detail => {
                Proc.runCommand(null, ["sh", "-c", restartScript, "sh", pid, detail?.unit ?? ""], (output, exitCode) => {
                    if (exitCode !== 0)
                        failed(process, exitCode === 3 ? I18n.tr("It runs in a terminal; restart it from there.", "toast body when restarting a terminal program") : "");
                }, 0, 15000);
            });
            return;
        case "system":
            DgopService.fetchProcessDetail(process.pid, detail => {
                if (DgopService.unlocked) {
                    DgopService.request("process.restartService", {
                        "pid": process.pid,
                        "unit": detail?.unit ?? ""
                    }, response => {
                        if (response.error)
                            failed(process, I18n.tr("Only the main process of a system service can be restarted.", "toast body when restarting another user's process"));
                    });
                    return;
                }
                Proc.runCommand(null, ["pkexec", "sh", "-c", systemRestartScript, "sh", pid, detail?.unit ?? ""], (output, exitCode) => {
                    if (exitCode === 4)
                        failed(process, I18n.tr("Only the main process of a system service can be restarted.", "toast body when restarting another user's process"));
                    else if (exitCode !== 0 && exitCode !== 126)
                        failed(process, "");
                }, 0, 60000);
            });
            return;
        }
    }
}
