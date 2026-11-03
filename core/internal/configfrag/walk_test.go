package configfrag

import "testing"

func TestRecordCountsAnIncludeTheCallerResolvesItself(t *testing.T) {
	walker := NewWalker(func(path string) bool { return path == "dms/binds.lua" })

	if walker.Record("other.lua") {
		t.Error("a non-dms module must not match")
	}
	if !walker.Record("dms/binds.lua") {
		t.Error("the dms module must match")
	}

	scan := walker.Scan()
	if scan.Count != 2 || scan.DMSPosition != 2 || !scan.DMSSeen {
		t.Errorf("scan = %+v, want count 2, position 2, seen", scan)
	}
}
