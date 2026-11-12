package distros

import "testing"

func TestDebianOBSRepoVersion_Kali(t *testing.T) {
	kali := &OSInfo{ID: "kali", VersionID: "2026.3", VersionCodename: "kali-rolling"}
	cases := []struct {
		name    string
		info    *OSInfo
		sources string
	}{
		{"apt sources", kali, "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware\n"},
		{"os-release only", kali, ""},
	}
	for _, c := range cases {
		got := debianOBSRepoVersion(c.info, debianAPTSuites(c.sources))
		if got != obsRepoDebianTesting {
			t.Errorf("%s: got %q, want %q", c.name, got, obsRepoDebianTesting)
		}
	}
}
