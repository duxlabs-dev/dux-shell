package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var switchUserCmd = &cobra.Command{
	Use:   "switch-user [target]",
	Short: "Switch to another active session on this seat",
	Long: `Switch the active VT to another running session.

With no target, prints the list of switchable sessions. Pass a username or a
numeric session ID to switch directly. Requires the target to already be a
running session on the same seat (use the greeter for a fresh login).`,
	Args: cobra.MaximumNArgs(1),
	Run:  runSwitchUser,
}

type sessionInfo struct {
	ID      string
	Name    string
	Seat    string
	TTY     string
	Type    string
	Class   string
	Active  bool
	State   string
	Current bool
}

func runSwitchUser(cmd *cobra.Command, args []string) {
	currentID := os.Getenv("XDG_SESSION_ID")
	sessions, err := listSessions(currentID)
	if err != nil {
		log.Fatalf("%v", err)
	}

	switchable := make([]sessionInfo, 0, len(sessions))
	for _, s := range sessions {
		if s.Class != "user" || s.State == "closing" || s.Current {
			continue
		}
		switchable = append(switchable, s)
	}

	if len(args) == 0 {
		if len(switchable) == 0 {
			fmt.Println("No other active sessions on this seat.")
			return
		}
		printSessions(switchable)
		return
	}

	target := args[0]
	picked, err := pickSession(switchable, target)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		if len(switchable) == 0 {
			fmt.Fprintln(os.Stderr, "No other active sessions on this seat. Only already-running sessions can be switched to.")
		} else {
			fmt.Fprintln(os.Stderr, "\nSwitchable sessions:")
			printSessions(switchable)
		}
		os.Exit(1)
	}

	if err := activateSession(picked.ID); err != nil {
		log.Fatalf("loginctl activate %s: %v", picked.ID, err)
	}
}

func listSessions(currentID string) ([]sessionInfo, error) {
	listOut, err := exec.Command("loginctl", "list-sessions", "--no-legend").Output()
	if err != nil {
		return nil, fmt.Errorf("loginctl list-sessions: %w", err)
	}

	var ids []string
	scanner := bufio.NewScanner(strings.NewReader(string(listOut)))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 0 {
			continue
		}
		ids = append(ids, fields[0])
	}

	out := make([]sessionInfo, 0, len(ids))
	for _, id := range ids {
		s, err := showSession(id)
		if err != nil {
			continue
		}
		s.Current = currentID != "" && s.ID == currentID
		out = append(out, s)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Name != out[j].Name {
			return out[i].Name < out[j].Name
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

func showSession(id string) (sessionInfo, error) {
	out, err := exec.Command("loginctl", "show-session", id,
		"-p", "Id", "-p", "Name", "-p", "Seat", "-p", "TTY",
		"-p", "Type", "-p", "Class", "-p", "Active", "-p", "State").Output()
	if err != nil {
		return sessionInfo{}, err
	}
	fields := map[string]string{}
	for line := range strings.SplitSeq(string(out), "\n") {
		idx := strings.IndexByte(line, '=')
		if idx <= 0 {
			continue
		}
		fields[line[:idx]] = line[idx+1:]
	}
	if fields["Id"] == "" {
		return sessionInfo{}, fmt.Errorf("session %s: no Id", id)
	}
	return sessionInfo{
		ID:     fields["Id"],
		Name:   fields["Name"],
		Seat:   fields["Seat"],
		TTY:    fields["TTY"],
		Type:   fields["Type"],
		Class:  fields["Class"],
		Active: fields["Active"] == "yes",
		State:  fields["State"],
	}, nil
}

func pickSession(sessions []sessionInfo, target string) (sessionInfo, error) {
	for _, s := range sessions {
		if s.ID == target {
			return s, nil
		}
	}
	matches := make([]sessionInfo, 0, 2)
	for _, s := range sessions {
		if s.Name == target {
			matches = append(matches, s)
		}
	}
	if len(matches) == 1 {
		return matches[0], nil
	}
	if len(matches) > 1 {
		ids := make([]string, len(matches))
		for i, m := range matches {
			ids[i] = m.ID
		}
		return sessionInfo{}, fmt.Errorf("%s has multiple active sessions (%s); pass a session ID instead", target, strings.Join(ids, ", "))
	}
	return sessionInfo{}, fmt.Errorf("no switchable session matches %q", target)
}

func activateSession(id string) error {
	return exec.Command("loginctl", "activate", id).Run()
}

func printSessions(sessions []sessionInfo) {
	fmt.Printf("%-6s %-12s %-8s %-8s %-8s\n", "ID", "USER", "TYPE", "SEAT", "TTY")
	for _, s := range sessions {
		tty := s.TTY
		if tty == "" {
			tty = "-"
		}
		seat := s.Seat
		if seat == "" {
			seat = "-"
		}
		fmt.Printf("%-6s %-12s %-8s %-8s %-8s\n", s.ID, s.Name, s.Type, seat, tty)
	}
}
