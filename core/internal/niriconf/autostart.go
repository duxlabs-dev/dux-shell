package niriconf

import (
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/sblinch/kdl-go/document"
)

// The XDG autostart folder the Autostart tab writes its .desktop entries to.
func autostartDir() string {
	configHome, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configHome, "autostart")
}

type autostartEntry struct {
	file     string
	programs []string
}

// autostartEntries lists the entries that would run at login: a Hidden=true entry starts nothing.
func autostartEntries(dir string) []autostartEntry {
	files, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var entries []autostartEntry
	for _, f := range files {
		if f.IsDir() || !strings.HasSuffix(f.Name(), ".desktop") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, f.Name()))
		if err != nil {
			continue
		}
		exec, hidden := desktopEntry(data)
		if hidden || exec == "" {
			continue
		}
		programs := append(execPrograms(exec), strings.TrimSuffix(f.Name(), ".desktop"))
		entries = append(entries, autostartEntry{file: f.Name(), programs: programs})
	}
	return entries
}

func desktopEntry(data []byte) (exec string, hidden bool) {
	inEntry := false
	for line := range strings.SplitSeq(string(data), "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "["):
			inEntry = line == "[Desktop Entry]"
		case inEntry && strings.HasPrefix(line, "Exec="):
			exec = strings.TrimSpace(strings.TrimPrefix(line, "Exec="))
		case inEntry && strings.HasPrefix(line, "Hidden="):
			hidden = strings.TrimSpace(strings.TrimPrefix(line, "Hidden=")) == "true"
		}
	}
	return exec, hidden
}

// execPrograms returns what an Exec line may name as its program: every argv basename, so a
// wrapper (`uwsm app -- foot`) still shows the app behind it.
func execPrograms(exec string) []string {
	var programs []string
	var cur strings.Builder
	quoted, escaped, started := false, false, false
	flush := func() {
		if started {
			programs = append(programs, filepath.Base(cur.String()))
			cur.Reset()
			started = false
		}
	}
	for _, r := range exec {
		switch {
		case escaped:
			cur.WriteRune(r)
			escaped = false
		case r == '\\' && quoted:
			escaped = true
		case r == '"':
			quoted = !quoted
			started = true
		case (r == ' ' || r == '\t') && !quoted:
			flush()
		default:
			cur.WriteRune(r)
			started = true
		}
	}
	flush()
	return programs
}

type spawnLine struct {
	file, program string
}

// spawn keeps the first argument of a spawn-at-startup: the program it opens at login.
func (d *doctor) spawn(n *document.Node, file string) {
	if len(n.Arguments) == 0 {
		return
	}
	d.spawns = append(d.spawns, spawnLine{file: file, program: n.Arguments[0].ValueString()})
}

// duplicateStartup reports an app both in XDG autostart and in a spawn-at-startup: it opens twice at login.
func (d *doctor) duplicateStartup(entries []autostartEntry) {
	for _, s := range d.spawns {
		program := filepath.Base(s.program)
		for _, e := range entries {
			if !slices.Contains(e.programs, program) {
				continue
			}
			d.add(Finding{Kind: KindDuplicateStartup, Severity: SeverityWarning, Subject: s.program, Files: []string{s.file, "autostart/" + e.file}})
			break
		}
	}
}
