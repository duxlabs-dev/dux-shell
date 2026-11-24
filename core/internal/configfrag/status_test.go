package configfrag

import "testing"

var hyprlandBinds = Messages{
	Missing:     "dms/binds.lua (or legacy binds.conf) does not exist",
	NotIncluded: "dms binds are not loaded from Hyprland config (require / source)",
	Overridden:  "Some DMS binds may be overridden by config binds",
	Active:      "DMS binds are active",
}

var allDomains = map[string]Messages{
	"hyprland binds": hyprlandBinds,
}

func TestMissingFragmentIsNotEffective(t *testing.T) {
	for domain, msgs := range allDomains {
		status := BuildStatus(NewScan(), false, 0, msgs)
		if status.Effective {
			t.Errorf("%s: a missing fragment must not be effective", domain)
		}
		if status.StatusMessage != msgs.Missing {
			t.Errorf("%s: message = %q, want %q", domain, status.StatusMessage, msgs.Missing)
		}
		if status.OverriddenBy != 0 {
			t.Errorf("%s: overriddenBy = %d, want 0", domain, status.OverriddenBy)
		}
	}
}

func TestExistingButNotIncludedIsNotEffective(t *testing.T) {
	for domain, msgs := range allDomains {
		scan := NewScan()
		scan.Count = 2
		status := BuildStatus(scan, true, 0, msgs)
		if status.Effective {
			t.Errorf("%s: an unincluded fragment must not be effective", domain)
		}
		if status.StatusMessage != msgs.NotIncluded {
			t.Errorf("%s: message = %q, want %q", domain, status.StatusMessage, msgs.NotIncluded)
		}
	}
}

func TestIncludedWithEntriesAfterReportsOverride(t *testing.T) {
	for domain, msgs := range allDomains {
		scan := IncludeScan{Count: 3, DMSPosition: 2, DMSSeen: true}
		status := BuildStatus(scan, true, 5, msgs)
		if !status.Effective {
			t.Errorf("%s: an overridden fragment is still effective", domain)
		}
		if status.OverriddenBy != 5 {
			t.Errorf("%s: overriddenBy = %d, want 5", domain, status.OverriddenBy)
		}
		if status.StatusMessage != msgs.Overridden {
			t.Errorf("%s: message = %q, want %q", domain, status.StatusMessage, msgs.Overridden)
		}
	}
}

func TestIncludedWithNothingAfterIsActive(t *testing.T) {
	for domain, msgs := range allDomains {
		scan := IncludeScan{Count: 1, DMSPosition: 1, DMSSeen: true}
		status := BuildStatus(scan, true, 0, msgs)
		if !status.Effective {
			t.Errorf("%s: an included fragment with nothing after it is effective", domain)
		}
		if status.OverriddenBy != 0 {
			t.Errorf("%s: overriddenBy = %d, want 0", domain, status.OverriddenBy)
		}
		if status.StatusMessage != msgs.Active {
			t.Errorf("%s: message = %q, want %q", domain, status.StatusMessage, msgs.Active)
		}
	}
}
