package distros

import "testing"

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
