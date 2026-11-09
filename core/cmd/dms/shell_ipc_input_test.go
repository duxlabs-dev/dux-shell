package main

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"testing/iotest"
)

func TestReadIslandActivityInput(t *testing.T) {
	args := []string{"call", "islandActivity", "publish", "calendar", "event", "-"}
	payload := "{\n  \"title\": \"Check-in\", \"body\": \"$(literal) `text`\"\n}\n"
	got, err := readIslandActivityInput(args, strings.NewReader(payload))
	if err != nil || got[5] != payload || args[5] != "-" {
		t.Fatalf("stdin was not preserved independently: %v, %v", got, err)
	}
	for _, untouched := range [][]string{
		{"call", "islandActivity", "publish", "calendar", "event", `{ "title": "inline" }`},
		{"call", "islandActivity", "publish", "calendar", "event"},
		{"call", "other", "publish", "calendar", "event", "-"},
		{"call", "islandActivity", "remove", "calendar", "-"},
	} {
		got, err := readIslandActivityInput(untouched, iotest.ErrReader(errors.New("must not read")))
		if err != nil || !slices.Equal(got, untouched) {
			t.Fatalf("non-stdin call changed: %v, %v", got, err)
		}
	}
}

func TestReadIslandActivityInputRejectsEmptyOversizedAndFailedReads(t *testing.T) {
	args := []string{"call", "islandActivity", "publish", "calendar", "event", "-"}
	for _, payload := range []string{"", " \n\t", strings.Repeat("x", 64*1024+1)} {
		if _, err := readIslandActivityInput(args, strings.NewReader(payload)); err == nil {
			t.Fatalf("accepted invalid input of length %d", len(payload))
		}
	}
	want := errors.New("read failed")
	if _, err := readIslandActivityInput(args, iotest.ErrReader(want)); !errors.Is(err, want) {
		t.Fatalf("read error not returned: %v", err)
	}
}
