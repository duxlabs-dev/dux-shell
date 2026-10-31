package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc/params"
	serverDgop "github.com/duxlabs-dev/dux-shell/core/internal/server/dgop"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/drives"
	"github.com/spf13/cobra"
)

// Started through pkexec when the system monitor is unlocked; exits when stdin closes.
var sysmonHelperCmd = &cobra.Command{
	Use:    "sysmon-helper",
	Short:  "Privileged process reader for the system monitor (started through pkexec)",
	Hidden: true,
	Args:   cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		go exitWhenOrphaned()
		serveSysmonHelper(os.Stdin, os.Stdout, sysmonHelperCall)
	},
}

const restartTimeout = 60 * time.Second

type helperRequest struct {
	ID     int            `json:"id"`
	Method string         `json:"method"`
	Params map[string]any `json:"params"`
}

func serveSysmonHelper(in io.Reader, out io.Writer, call func(string, map[string]any) (any, error)) {
	var mu sync.Mutex
	var wg sync.WaitGroup
	write := func(v map[string]any) {
		data, _ := json.Marshal(v)
		mu.Lock()
		defer mu.Unlock()
		if _, err := out.Write(append(data, '\n')); err != nil {
			// The shell that reads us is gone.
			os.Exit(0)
		}
	}
	scanner := bufio.NewScanner(in)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		var req helperRequest
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, err := call(req.Method, req.Params)
			if err != nil {
				write(map[string]any{"id": req.ID, "error": err.Error()})
				return
			}
			write(map[string]any{"id": req.ID, "result": result})
		}()
	}
	wg.Wait()
}

func sysmonHelperCall(method string, p map[string]any) (any, error) {
	switch method {
	case "process.signal":
		pid, err := helperPid(p)
		if err != nil {
			return nil, err
		}
		sig := syscall.SIGTERM
		if params.StringOpt(p, "signal", "TERM") == "KILL" {
			sig = syscall.SIGKILL
		}
		return true, syscall.Kill(pid, sig)
	case "process.tree":
		pid, err := helperPid(p)
		if err != nil {
			return nil, err
		}
		for _, child := range treeOrder(pid, readParents(), readComm, params.StringSlice(p, "skip")) {
			syscall.Kill(child, syscall.SIGTERM)
		}
		return true, syscall.Kill(pid, syscall.SIGTERM)
	case "process.restartService":
		pid, err := helperPid(p)
		if err != nil {
			return nil, err
		}
		unit := params.StringOpt(p, "unit", "")
		if !strings.HasSuffix(unit, ".service") || strings.HasPrefix(unit, "-") {
			return nil, errors.New("not a service")
		}
		ctx, cancel := context.WithTimeout(context.Background(), restartTimeout)
		defer cancel()
		mainPid, err := exec.CommandContext(ctx, "systemctl", "show", "-p", "MainPID", "--value", "--", unit).Output()
		if err != nil || strings.TrimSpace(string(mainPid)) != strconv.Itoa(pid) {
			return nil, errors.New("not the main process of " + unit)
		}
		return true, exec.CommandContext(ctx, "systemctl", "restart", "--", unit).Run()
	case "drives.smart":
		return drives.FullReport(params.StringOpt(p, "device", ""))
	}
	if strings.HasPrefix(method, "dgop.") {
		return serverDgop.Call(method, p)
	}
	return nil, fmt.Errorf("unknown method: %s", method)
}

// helperPid rejects PID 1 and below: init is never signalled.
func helperPid(p map[string]any) (int, error) {
	pid, err := params.Int(p, "pid")
	if err != nil || pid <= 1 {
		return 0, errors.New("invalid pid")
	}
	return pid, nil
}

// treeOrder lists pid's descendants children first. A child whose name is in skip keeps its whole subtree.
func treeOrder(pid int, parents map[int]int, comm func(int) string, skip []string) []int {
	children := map[int][]int{}
	for child, parent := range parents {
		children[parent] = append(children[parent], child)
	}
	var out []int
	// The parent map is a racy /proc snapshot, so a reused PID can form a cycle.
	seen := map[int]bool{pid: true}
	var walk func(int)
	walk = func(p int) {
		for _, c := range children[p] {
			if seen[c] || slices.Contains(skip, strings.ToLower(comm(c))) {
				continue
			}
			seen[c] = true
			walk(c)
			out = append(out, c)
		}
	}
	walk(pid)
	return out
}

// readParents maps every PID to its parent from /proc/<pid>/stat (the field after the ')' that ends the name).
func readParents() map[int]int {
	parents := map[int]int{}
	entries, _ := os.ReadDir("/proc")
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		data, err := os.ReadFile("/proc/" + e.Name() + "/stat")
		if err != nil {
			continue
		}
		s := string(data)
		i := strings.LastIndexByte(s, ')')
		if i < 0 {
			continue
		}
		fields := strings.Fields(s[i+1:])
		if len(fields) < 2 {
			continue
		}
		if ppid, err := strconv.Atoi(fields[1]); err == nil {
			parents[pid] = ppid
		}
	}
	return parents
}

func readComm(pid int) string {
	data, _ := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/comm")
	return strings.TrimSpace(string(data))
}

// exitWhenOrphaned stops the helper if the shell that started it dies without closing stdin.
func exitWhenOrphaned() {
	parent := os.Getppid()
	for range time.Tick(2 * time.Second) {
		if os.Getppid() != parent {
			os.Exit(0)
		}
	}
}
