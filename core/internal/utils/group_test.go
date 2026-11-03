package utils

import "testing"

const testGroupData = `root:x:0:brltty,root
sys:x:3:bin,testuser
mem:x:8:
ftp:x:11:
mail:x:12:
log:x:19:
smmsp:x:25:
proc:x:26:
games:x:50:
lock:x:54:
network:x:90:
floppy:x:94:
scanner:x:96:
power:x:98:
nobody:x:65534:
adm:x:999:daemon
wheel:x:998:testuser
utmp:x:997:
audio:x:996:brltty
disk:x:995:
input:x:994:brltty,testuser,greeter
kmem:x:993:
kvm:x:992:libvirt-qemu,qemu,testuser
lp:x:991:cups,testuser
optical:x:990:
render:x:989:
sgx:x:988:
storage:x:987:
tty:x:5:brltty
uucp:x:986:brltty
video:x:985:cosmic-greeter,greeter,testuser
users:x:984:
groups:x:983:
systemd-journal:x:982:
rfkill:x:981:
bin:x:1:daemon
daemon:x:2:bin
http:x:33:
dbus:x:81:
systemd-coredump:x:980:
systemd-network:x:979:
systemd-oom:x:978:
systemd-journal-remote:x:977:
systemd-resolve:x:976:
systemd-timesync:x:975:
tss:x:974:
uuidd:x:973:
alpm:x:972:
polkitd:x:102:
testuser:x:1000:
avahi:x:971:
git:x:970:
nvidia-persistenced:x:143:
i2c:x:969:testuser
seat:x:968:
rtkit:x:133:
brlapi:x:967:brltty
gdm:x:120:
brltty:x:966:
colord:x:965:
flatpak:x:964:
geoclue:x:963:testuser
gnome-remote-desktop:x:962:
saned:x:961:
usbmux:x:140:
cosmic-greeter:x:960:
greeter:x:959:testuser
openvpn:x:958:
nm-openvpn:x:957:
named:x:40:
_talkd:x:956:
keyd:x:955:
cups:x:209:testuser
docker:x:954:testuser
mysql:x:953:
radicale:x:952:
onepassword:x:1001:
nixbld:x:951:nixbld01,nixbld02,nixbld03,nixbld04,nixbld05,nixbld06,nixbld07,nixbld08,nixbld09,nixbld10
virtlogin:x:940:
libvirt:x:939:testuser
libvirt-qemu:x:938:
qemu:x:937:
dnsmasq:x:936:
clock:x:935:
dms-greeter:x:1002:greeter,testuser
pcscd:x:934:
test:x:1003:
empower:x:933:
`

func TestHasGroupData(t *testing.T) {
	tests := []struct {
		group string
		want  bool
	}{
		{"greeter", true},
		{"root", true},
		{"cosmic-greeter", true},
		{"nonexistent", false},
		{"greet", false},
	}

	for _, tt := range tests {
		if got := HasGroupData(tt.group, testGroupData); got != tt.want {
			t.Errorf("HasGroupData(%q) = %v, want %v", tt.group, got, tt.want)
		}
	}
}

func TestFindGroupData(t *testing.T) {
	tests := []struct {
		name       string
		candidates []string
		wantGroup  string
		wantFound  bool
	}{
		{"first match wins", []string{"greeter", "greetd", "_greeter"}, "greeter", true},
		{"fallback to second", []string{"greetd", "greeter"}, "greeter", true},
		{"none found", []string{"_greetd", "greetd"}, "", false},
	}

	for _, tt := range tests {
		got, found := FindGroupData(testGroupData, tt.candidates...)
		if got != tt.wantGroup || found != tt.wantFound {
			t.Errorf("%s: FindGroupData(%v) = (%q, %v), want (%q, %v)",
				tt.name, tt.candidates, got, found, tt.wantGroup, tt.wantFound)
		}
	}
}
