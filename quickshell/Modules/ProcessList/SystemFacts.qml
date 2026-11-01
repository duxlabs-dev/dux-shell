import QtQuick
import Quickshell.Io
import qs.Common

// Versions, themes, packages and boot facts no service keeps, read by one read-only script per refresh.
Item {
    id: root

    property var facts: ({})
    property bool loaded: false
    property var doctor: null
    readonly property bool doctorRunning: doctorProc.running

    // Every command only reads. No GL, Vulkan or PCI probe: creating a context or touching config space wakes a suspended GPU.
    readonly property string script: `
v() { command -v "$1" >/dev/null 2>&1; }
p() { printf '%s=%s\\n' "$1" "$(printf '%s' "$2" | head -n1 | tr -d '\\r')"; }
p qs "$(qs --version 2>/dev/null)"
v hyprctl && p wm.hyprland "$(hyprctl version 2>/dev/null)"
v niri && p wm.niri "$(niri --version 2>/dev/null)"
v sway && p wm.sway "$(sway --version 2>/dev/null)"
v scroll && p wm.scroll "$(scroll --version 2>/dev/null)"
v labwc && p wm.labwc "$(labwc --version 2>/dev/null)"
v miracle-wm && p wm.miracle "$(miracle-wm --version 2>/dev/null)"
p init "$(systemctl --version 2>/dev/null)"
p shellver "$("\${SHELL:-sh}" --version 2>/dev/null)"
if v gsettings; then
  for k in gtk-theme icon-theme cursor-theme cursor-size font-name; do p "gs.$k" "$(gsettings get org.gnome.desktop.interface $k 2>/dev/null | tr -d "'")"; done
fi
v pacman && p pkg.pacman "$(pacman -Qq 2>/dev/null | wc -l)"
v dpkg-query && p pkg.dpkg "$(dpkg-query -f '.\\n' -W 2>/dev/null | wc -l)"
v rpm && p pkg.rpm "$(rpm -qa 2>/dev/null | wc -l)"
v xbps-query && p pkg.xbps "$(xbps-query -l 2>/dev/null | wc -l)"
v apk && p pkg.apk "$(apk info 2>/dev/null | wc -l)"
v flatpak && p pkg.flatpak "$(flatpak list 2>/dev/null | wc -l)"
v snap && p pkg.snap "$(snap list 2>/dev/null | tail -n +2 | wc -l)"
[ -d /run/current-system ] && v nix-store && p pkg.nix "$(nix-store -qR /run/current-system 2>/dev/null | wc -l)"
v pipewire && p pipewire "$(pipewire --version 2>/dev/null | sed -n 's/.*libpipewire \\([0-9.]*\\).*/\\1/p')"
mesa=$(ls /usr/lib/libgallium-*.so /usr/lib64/libgallium-*.so /usr/lib/*-linux-gnu/libgallium-*.so 2>/dev/null | head -n1 | sed 's/.*libgallium-//;s/\\.so$//')
[ -z "$mesa" ] && v pkg-config && mesa=$(pkg-config --modversion dri 2>/dev/null)
p mesa "$mesa"
icd=$(ls /usr/share/vulkan/icd.d/*.json /etc/vulkan/icd.d/*.json 2>/dev/null)
if [ -n "$icd" ]; then
  p vk.api "$(cat $icd | grep -o '"api_version" *: *"[^"]*"' | sed 's/.*: *"//;s/"//' | sort -V | tail -n1)"
  p vk.driver "$(cat $icd | grep -o '"library_path" *: *"[^"]*"' | sed 's/"$//;s|.*[/"]||;s/^lib\\(vulkan\\|GLX\\)_//;s/\\.so.*//;s/^radeon$/radv/;s/^intel$/anv/;s/^intel_hasvk$/hasvk/;s/^nouveau$/nvk/' | grep -v '^lvp' | sort -u | paste -sd, - | sed 's/,/, /g')"
fi
[ -d /sys/firmware/efi ] && p boot.uefi yes
f=$(ls /sys/firmware/efi/efivars/LoaderInfo-* 2>/dev/null | head -n1)
[ -n "$f" ] && p boot.loader "$(tail -c +5 "$f" 2>/dev/null | tr -d '\\000')"
f=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -n1)
[ -n "$f" ] && p boot.secure "$(od -An -t u1 -j4 -N1 "$f" 2>/dev/null | tr -d ' ')"
for k in chassis_type product_name sys_vendor board_vendor board_name bios_version bios_date; do
  [ -r /sys/class/dmi/id/$k ] && p dmi.$k "$(cat /sys/class/dmi/id/$k 2>/dev/null)"
done
p shell "$(basename "\${SHELL:-}")"
p lang "\${LC_ALL:-\${LANG:-}}"
p session "\${XDG_SESSION_TYPE:-}"
p desktop "\${XDG_CURRENT_DESKTOP:-}"
p uwsm "\${UWSM_FINALIZE_VARNAMES:+yes}"
p qpa "\${QT_QPA_PLATFORMTHEME:-}"
`

    function refresh() {
        if (!factsProc.running)
            factsProc.running = true;
        runDoctor();
    }

    function runDoctor() {
        if (!doctorProc.running)
            doctorProc.running = true;
    }

    Process {
        id: factsProc
        command: ["sh", "-c", root.script]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0 && line.slice(i + 1).trim() !== "")
                        map[line.slice(0, i)] = line.slice(i + 1).trim();
                }
                root.facts = map;
                root.loaded = true;
            }
        }
    }

    Process {
        id: doctorProc
        command: [Proc.dmsBin, "doctor", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.doctor = JSON.parse(text);
                } catch (e) {
                    root.doctor = null;
                }
            }
        }
    }
}
