package configfrag

type IncludeScan struct {
	Count       int
	DMSPosition int
	DMSSeen     bool
}

func NewScan() IncludeScan {
	return IncludeScan{DMSPosition: -1}
}

type Walker struct {
	isDMSFragment func(string) bool
	scan          IncludeScan
}

func NewWalker(isDMSFragment func(string) bool) *Walker {
	return &Walker{isDMSFragment: isDMSFragment, scan: NewScan()}
}

func (w *Walker) Scan() IncludeScan {
	return w.scan
}

func (w *Walker) Included() bool {
	return w.scan.DMSSeen
}

func (w *Walker) RecordMatch(matched bool) bool {
	w.scan.Count++
	if !matched {
		return false
	}
	w.scan.DMSSeen = true
	w.scan.DMSPosition = w.scan.Count
	return true
}

func (w *Walker) Record(sourcePath string) bool {
	return w.RecordMatch(w.isDMSFragment != nil && w.isDMSFragment(sourcePath))
}
