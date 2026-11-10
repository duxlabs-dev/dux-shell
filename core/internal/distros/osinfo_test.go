package distros

import (
	"testing"

	"github.com/spf13/afero"
)

func TestIsUnsupportedDistro_EnterpriseLinux(t *testing.T) {
	cases := []struct {
		id, version string
		unsupported bool
	}{
		{"rhel", "10.1", false},
		{"centos", "10", false},
		{"almalinux", "10.1", false},
		{"rocky", "11.0", false},
		{"rhel", "9.6", true},
		{"rocky", "9", true},
		{"centos", "", true},
	}
	for _, c := range cases {
		if got := IsUnsupportedDistro(c.id, c.version); got != c.unsupported {
			t.Errorf("IsUnsupportedDistro(%q, %q) = %v, want %v", c.id, c.version, got, c.unsupported)
		}
	}
}

func TestGetOSInfo_DebianDerivatives(t *testing.T) {
	cases := []struct {
		name, osRelease, want string
	}{
		{"lmde", "ID=linuxmint\nID_LIKE=debian\nNAME=LMDE\nVERSION_ID=\"7\"\nVERSION_CODENAME=gigi\nDEBIAN_CODENAME=trixie\n", "lmde"},
		{"soplos", "ID=soplos\nID_LIKE=debian\nVERSION_ID=\"2026.11\"\nVERSION_CODENAME=tyron\n", "soplos"},
		{"ubuntu mint", "ID=linuxmint\nID_LIKE=\"ubuntu debian\"\nVERSION_ID=\"22.3\"\nUBUNTU_CODENAME=noble\n", ""},
	}
	for _, c := range cases {
		fs := afero.NewMemMapFs()
		writeOSRelease(t, fs, c.osRelease)
		info, err := getOSInfo(fs, "amd64")
		if c.want == "" {
			if err == nil {
				t.Errorf("%s: resolved to %q, want unsupported", c.name, info.Distribution.ID)
			}
			continue
		}
		if err != nil || info.Distribution.ID != c.want {
			t.Errorf("%s: got %+v, %v, want %q", c.name, info, err, c.want)
		}
	}
}
