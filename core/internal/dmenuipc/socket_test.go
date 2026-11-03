package dmenuipc

import (
	"encoding/json"
	"net"
	"testing"
	"time"
)

func TestSessionAcceptAndSelect(t *testing.T) {
	sess, err := Listen()
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	defer sess.Close()

	peerDone := make(chan error, 1)
	go func() {
		peerDone <- func() error {
			conn, err := net.Dial("unix", sess.Path())
			if err != nil {
				return err
			}
			defer conn.Close()

			dec := json.NewDecoder(conn)

			var header envelope
			if err := dec.Decode(&header); err != nil {
				return err
			}
			if header.Type != "header" || header.Prompt != "pick:" {
				t.Errorf("unexpected header: %+v", header)
			}

			var got []string
			for {
				var e envelope
				if err := dec.Decode(&e); err != nil {
					return err
				}
				if e.Type == "end" {
					break
				}
				if e.Type != "item" {
					t.Errorf("unexpected message while reading items: %+v", e)
					continue
				}
				got = append(got, e.Text)
			}
			want := []string{"a", "b", "c"}
			if len(got) != len(want) {
				t.Errorf("items = %v, want %v", got, want)
			} else {
				for i := range want {
					if got[i] != want[i] {
						t.Errorf("items = %v, want %v", got, want)
						break
					}
				}
			}

			return json.NewEncoder(conn).Encode(envelope{Type: "select", Kind: "row", Index: 1, Text: "b", FilterText: "b"})
		}()
	}()

	conn, err := sess.Accept(2 * time.Second)
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	defer conn.Close()

	if err := conn.SendHeader(Header{Prompt: "pick:"}); err != nil {
		t.Fatalf("SendHeader: %v", err)
	}
	for _, item := range []string{"a", "b", "c"} {
		if err := conn.SendItem(item, nil); err != nil {
			t.Fatalf("SendItem(%q): %v", item, err)
		}
	}
	if err := conn.SendEnd(); err != nil {
		t.Fatalf("SendEnd: %v", err)
	}

	sel, ok, err := conn.ReadSelection()
	if err != nil {
		t.Fatalf("ReadSelection: %v", err)
	}
	if !ok {
		t.Fatalf("ReadSelection: ok = false, want true")
	}
	if sel.Kind != "row" || sel.Index != 1 || sel.Text != "b" {
		t.Fatalf("ReadSelection: sel = %+v, want kind=row index=1 text=b", sel)
	}

	if err := <-peerDone; err != nil {
		t.Fatalf("peer: %v", err)
	}
}

func TestSessionCancelClosesWithoutSelection(t *testing.T) {
	sess, err := Listen()
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	defer sess.Close()

	go func() {
		conn, err := net.Dial("unix", sess.Path())
		if err != nil {
			return
		}
		// Drain the header/end messages, then close without ever sending
		// a "select" — this is what a cancelled/closed modal does.
		dec := json.NewDecoder(conn)
		for {
			var e envelope
			if err := dec.Decode(&e); err != nil || e.Type == "end" {
				break
			}
		}
		conn.Close()
	}()

	conn, err := sess.Accept(2 * time.Second)
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	defer conn.Close()

	_ = conn.SendHeader(Header{Prompt: "pick:"})
	_ = conn.SendEnd()

	sel, ok, err := conn.ReadSelection()
	if err != nil {
		t.Fatalf("ReadSelection: unexpected error: %v", err)
	}
	if ok {
		t.Fatalf("ReadSelection: ok = true, want false (cancellation); sel = %+v", sel)
	}
}

func TestSessionMultiSelectResponse(t *testing.T) {
	sess, err := Listen()
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	defer sess.Close()

	go func() {
		conn, err := net.Dial("unix", sess.Path())
		if err != nil {
			return
		}
		defer conn.Close()
		dec := json.NewDecoder(conn)
		for {
			var e envelope
			if err := dec.Decode(&e); err != nil || e.Type == "end" {
				break
			}
		}
		json.NewEncoder(conn).Encode(envelope{
			Type: "select",
			Kind: "multi",
			Items: []SelectedRow{
				{Index: 0, Text: "a"},
				{Index: 2, Text: "c"},
			},
			FilterText: "",
		})
	}()

	conn, err := sess.Accept(2 * time.Second)
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	defer conn.Close()

	_ = conn.SendHeader(Header{Prompt: "pick:", MultiSelect: true})
	_ = conn.SendEnd()

	sel, ok, err := conn.ReadSelection()
	if err != nil {
		t.Fatalf("ReadSelection: %v", err)
	}
	if !ok || sel.Kind != "multi" || len(sel.Items) != 2 {
		t.Fatalf("ReadSelection: sel = %+v", sel)
	}
	if sel.Items[0] != (SelectedRow{Index: 0, Text: "a"}) || sel.Items[1] != (SelectedRow{Index: 2, Text: "c"}) {
		t.Fatalf("ReadSelection: items = %+v", sel.Items)
	}
}

func TestSessionItemMetaAndKeybindRoundTrip(t *testing.T) {
	sess, err := Listen()
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	defer sess.Close()

	go func() {
		conn, err := net.Dial("unix", sess.Path())
		if err != nil {
			return
		}
		defer conn.Close()
		dec := json.NewDecoder(conn)

		var header envelope
		if err := dec.Decode(&header); err != nil {
			return
		}
		if len(header.Keybinds) != 1 || header.Keybinds[0] != (Keybind{N: 1, Key: "ctrl+e"}) {
			t.Errorf("unexpected header keybinds: %+v", header.Keybinds)
		}

		var got *envelope
		for {
			var e envelope
			if err := dec.Decode(&e); err != nil || e.Type == "end" {
				break
			}
			if e.Type == "item" {
				ec := e
				got = &ec
			}
		}
		if got == nil || got.Row == nil || got.Row.Icon != "firefox" || got.Row.Info != "firefox.desktop" {
			t.Errorf("unexpected item: %+v", got)
			return
		}

		json.NewEncoder(conn).Encode(envelope{
			Type:     "select",
			Kind:     "row",
			Index:    0,
			Text:     "Firefox",
			Info:     "firefox.desktop",
			KeybindN: 1,
		})
	}()

	conn, err := sess.Accept(2 * time.Second)
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	defer conn.Close()

	_ = conn.SendHeader(Header{Prompt: "pick:", Keybinds: []Keybind{{N: 1, Key: "ctrl+e"}}})
	_ = conn.SendItem("Firefox", &ItemMeta{Icon: "firefox", Info: "firefox.desktop"})
	_ = conn.SendEnd()

	sel, ok, err := conn.ReadSelection()
	if err != nil {
		t.Fatalf("ReadSelection: %v", err)
	}
	if !ok || sel.Info != "firefox.desktop" || sel.KeybindN != 1 {
		t.Fatalf("ReadSelection: sel = %+v", sel)
	}
}

func TestSessionAcceptTimesOutWhenNobodyConnects(t *testing.T) {
	sess, err := Listen()
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	defer sess.Close()

	start := time.Now()
	_, err = sess.Accept(200 * time.Millisecond)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatalf("Accept: expected timeout error, got nil")
	}
	if elapsed > 2*time.Second {
		t.Fatalf("Accept: took %v, expected to return promptly after the deadline", elapsed)
	}
}
