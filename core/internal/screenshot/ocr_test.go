package screenshot

import "testing"

func TestParseTesseractLangs(t *testing.T) {
	out := "List of available languages in \"/usr/share/tessdata/\" (3):\neng\nosd\nvie\n"
	if got := parseTesseractLangs(out); got != "eng+vie" {
		t.Fatalf("parseTesseractLangs = %q, want %q", got, "eng+vie")
	}

	empty := "List of available languages in \"/usr/share/tessdata/\" (1):\nosd\n"
	if got := parseTesseractLangs(empty); got != "eng" {
		t.Fatalf("parseTesseractLangs(osd only) = %q, want %q", got, "eng")
	}
}

func TestResolveOCRLang(t *testing.T) {
	if got := ResolveOCRLang(" jpn+eng "); got != "jpn+eng" {
		t.Fatalf("ResolveOCRLang = %q, want %q", got, "jpn+eng")
	}
}
