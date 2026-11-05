pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root

    // Ending one of these takes the desktop down. Process names are cut to 15 characters.
    readonly property var sessionNames: ["systemd", "(sd-pam)", "sd-pam", "dbus-broker", "dbus-broker-lau", "dbus-daemon"].concat(Object.keys(reloadCommands))
    readonly property var treeSkipNames: sessionNames.concat(["qs", "quickshell", "dms", "polkitd"])
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

    readonly property var priorities: [
        {
            "nice": -20,
            "label": I18n.tr("Highest", "process priority preset")
        },
        {
            "nice": -10,
            "label": I18n.tr("High", "process priority preset")
        },
        {
            "nice": 0,
            "label": I18n.tr("Normal", "process priority preset")
        },
        {
            "nice": 10,
            "label": I18n.tr("Low", "process priority preset")
        },
        {
            "nice": 19,
            "label": I18n.tr("Lowest", "process priority preset")
        }
    ]

    // $1 pid, $2 names to skip, $3 signal for the descendants, $4 for the root. A skipped child keeps its whole subtree.
    // STOP goes parents first, or a shell sees its foreground job stop and takes the terminal back. The rest goes
    // children first, since a dead root's children can't be found. A stopped process only acts on TERM once continued.
    readonly property string treeScript: 's=$3; send() { kill -s "$1" "$2" || return; [ "$1" != TERM ] || kill -s CONT "$2" 2>/dev/null; return 0; }; [ "$s" != STOP ] || send STOP "$1"; walk() ( for c in $(pgrep -P "$1"); do n=$(tr "[:upper:]" "[:lower:]" < /proc/$c/comm 2>/dev/null) || continue; case " $2 " in *" $n "*) continue ;; esac; [ "$s" != STOP ] || send STOP "$c" 2>/dev/null; walk "$c" "$2"; [ "$s" = STOP ] || send "$s" "$c" 2>/dev/null; done ); walk "$1" "$2"; send "$4" "$1"'

    // $1 nice, $2 pid, $3 names to skip, $4 non-empty for a merged row: descendants linked by the root's executable, as
    // dgop merges them. renice reaches one thread per id. Only the root decides the result; the rest can exit mid-way.
    readonly property string priorityScript: 'n=$1; s=$3; renice "$n" -p "$2" >/dev/null || exit 1; threads() ( cd "/proc/$1/task" 2>/dev/null && renice "$n" -p * >/dev/null 2>&1 ); walk() ( for c in $(pgrep -P "$1"); do [ "$(readlink "/proc/$c/exe" 2>/dev/null)" = "$x" ] || continue; m=$(tr "[:upper:]" "[:lower:]" < /proc/$c/comm 2>/dev/null) || continue; case " $s " in *" $m "*) continue ;; esac; threads "$c"; walk "$c"; done ); threads "$2"; if [ -n "$4" ]; then x=$(readlink "/proc/$2/exe") && [ -n "$x" ] && walk "$2"; fi; exit 0'

    // $1 pid, $2 its systemd unit, $3 the script that ends a paused tree, $4 names to skip. Only a unit's main process restarts
    // through systemd (apps share the compositor's unit). Terminal programs exit 3. Anything else is relaunched with
    // its command line, environment and directory.
    readonly property string restartScript: 'p=$1; u=$2; e=$3; k=$4; case "$u" in *.service) [ "$(systemctl --user show -p MainPID --value "$u" 2>/dev/null)" = "$p" ] && exec systemctl --user restart "$u" ;; esac; s=$(cat "/proc/$p/stat") || exit 1; set -- ${s##*) }; [ "$5" = 0 ] || exit 3; t=$(mktemp -d) || exit 1; trap "rm -r \\"$t\\"" EXIT; cp "/proc/$p/cmdline" "$t/cmd" && cp "/proc/$p/environ" "$t/env" && cwd=$(readlink "/proc/$p/cwd") || exit 1; if [ -n "$e" ]; then sh -c "$e" sh "$p" "$k" CONT TERM || exit 1; else kill "$p" || exit 1; fi; i=0; while kill -0 "$p" 2>/dev/null; do i=$((i + 1)); [ "$i" -gt 100 ] && exit 1; sleep 0.1; done; cd "$cwd" 2>/dev/null || cd; run="setsid -f"; command -v systemd-run >/dev/null && run="$run systemd-run --user --scope --quiet --collect"; cat "$t/env" "$t/cmd" | xargs -0 $run env -i >/dev/null 2>&1'
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

    function isPaused(process) {
        return process?.status === "T";
    }

    // The root helper is a "dms" of another user; stopping it would hang sampling.
    function canPause(process) {
        // Kernel threads (PID 2 and its children) ignore SIGSTOP.
        const kernel = process?.pid === 2 || process?.ppid === 2;
        return canEnd(process) && !kernel && (process?.status ?? "") !== "" && !isDms(process) && !treeSkipNames.includes(name(process));
    }

    function canSetPriority(process) {
        return canEnd(process) && (process?.nice ?? null) !== null;
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

    function treeArgv(process, signal, rootSignal) {
        return ["sh", "-c", treeScript, "sh", String(process.pid), treeSkipNames.join(" "), signal, rootSignal];
    }

    function run(action, process) {
        const pid = String(process?.pid ?? 0);
        if (!canEnd(process))
            return;
        const paused = isPaused(process);
        // Unlocked, the root helper ends other users' processes without another password prompt.
        if (!isOwn(process) && DgopService.unlocked && action !== "restart") {
            const params = {
                "pid": process.pid,
                "skip": treeSkipNames,
                "resume": paused
            };
            if (action === "force")
                params.signal = "KILL";
            DgopService.request(action === "tree" ? "process.tree" : "process.signal", params, null);
            return;
        }
        const auth = isOwn(process) ? [] : ["pkexec"];
        switch (action) {
        case "quit":
            Quickshell.execDetached(auth.concat(paused ? treeArgv(process, "CONT", "TERM") : ["kill", pid]));
            break;
        case "force":
            Quickshell.execDetached(auth.concat(paused ? treeArgv(process, "CONT", "KILL") : ["kill", "-9", pid]));
            break;
        case "tree":
            Quickshell.execDetached(auth.concat(treeArgv(process, "TERM", "TERM")));
            break;
        case "restart":
            restart(process);
            break;
        }
    }

    function setPaused(process, paused) {
        if (!canPause(process))
            return;
        const signal = paused ? "STOP" : "CONT";
        const failure = paused ? I18n.tr("Failed to pause %1", "toast title, %1 is a process name") : I18n.tr("Failed to resume %1", "toast title, %1 is a process name");
        runChecked(!isOwn(process), "process.tree", {
            "pid": process.pid,
            "skip": treeSkipNames,
            "signal": signal
        }, treeArgv(process, signal, signal), failure.arg(process.command ?? ""));
    }

    // The preset closest to a nice value, so values set elsewhere still read as a level.
    function priorityPreset(nice) {
        if (nice === null || nice === undefined)
            return null;
        return priorities.reduce((best, p) => Math.abs(p.nice - nice) < Math.abs(best.nice - nice) ? p : best);
    }

    function setPriority(process, nice) {
        if (!canSetPriority(process))
            return;
        const merged = (process.childCount ?? 0) > 0;
        // Members of a merged row can differ from the root, and the row can't show it.
        if (nice === process.nice && !merged)
            return;
        runChecked(!isOwn(process) || nice < process.nice, "process.nice", {
            "pid": process.pid,
            "nice": nice,
            "merged": merged,
            "skip": treeSkipNames
        }, ["sh", "-c", priorityScript, "sh", String(nice), String(process.pid), treeSkipNames.join(" "), merged ? "1" : ""], I18n.tr("Failed to change priority of %1", "toast title, %1 is a process name").arg(process.command ?? ""));
    }

    // Reports failure and asks for an early sample once the action, including any password prompt, is over.
    function runChecked(needsRoot, method, params, argv, failure) {
        if (needsRoot && DgopService.unlocked) {
            DgopService.request(method, params, response => {
                if (response.error)
                    ToastService.showError(failure, response.error);
                DgopService.refreshSoon();
            });
            return;
        }
        Proc.runCommand(null, needsRoot ? ["pkexec"].concat(argv) : argv, (output, exitCode) => {
            if (exitCode !== 0 && exitCode !== 126)
                ToastService.showError(failure, "");
            DgopService.refreshSoon();
        }, 0, 60000);
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
                Proc.runCommand(null, ["sh", "-c", restartScript, "sh", pid, detail?.unit ?? "", isPaused(process) ? treeScript : "", treeSkipNames.join(" ")], (output, exitCode) => {
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
