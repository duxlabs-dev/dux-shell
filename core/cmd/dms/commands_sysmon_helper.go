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
		pid, sig, err := helperPidSignal(p)
		if err != nil {
			return nil, err
		}
		if params.BoolOpt(p, "resume", false) {
			for _, child := range helperTree(pid, p) {
				_ = sendSignal(child, syscall.SIGCONT)
			}
		}
		return true, sendSignal(pid, sig)
	case "process.tree":
		pid, sig, err := helperPidSignal(p)
		if err != nil {
			return nil, err
		}
		var rootErr error
		for _, target := range signalOrder(pid, helperTree(pid, p), sig) {
			if err := sendSignal(target, sig); target == pid {
				rootErr = err
			}
		}
		return true, rootErr
	case "process.nice":
		pid, err := helperPid(p)
		if err != nil {
			return nil, err
		}
		nice, err := helperNice(p)
		if err != nil {
			return nil, err
		}
		if err := setNice(pid, nice); err != nil {
			return nil, err
		}
		if params.BoolOpt(p, "merged", false) {
			for _, member := range mergedChildren(pid, readParents(), readExe, readComm, params.StringSlice(p, "skip")) {
				_ = setNice(member, nice)
			}
		}
		return true, nil
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

var helperSignals = map[string]syscall.Signal{
	"TERM": syscall.SIGTERM,
	"KILL": syscall.SIGKILL,
	"STOP": syscall.SIGSTOP,
	"CONT": syscall.SIGCONT,
}

// helperPidSignal validates both before anything is signalled; an absent signal means TERM.
// The helper never stops itself, since nothing could resume it.
func helperPidSignal(p map[string]any) (int, syscall.Signal, error) {
	pid, err := helperPid(p)
	if err != nil {
		return 0, 0, err
	}
	name := any("TERM")
	if v, present := p["signal"]; present {
		name = v
	}
	s, _ := name.(string)
	sig, ok := helperSignals[s]
	if !ok || (sig == syscall.SIGSTOP && pid == os.Getpid()) {
		return 0, 0, errors.New("unsupported signal")
	}
	return pid, sig, nil
}

// sendSignal follows TERM with CONT: a stopped process only acts on it once continued.
func sendSignal(pid int, sig syscall.Signal) error {
	err := syscall.Kill(pid, sig)
	if err == nil && sig == syscall.SIGTERM {
		_ = syscall.Kill(pid, syscall.SIGCONT)
	}
	return err
}

func helperTree(pid int, p map[string]any) []int {
	return treeOrder(pid, readParents(), readComm, params.StringSlice(p, "skip"), os.Getpid())
}

// signalOrder puts the root after its children, which a dead root would lose. STOP goes the other way,
// parents first, or a shell sees its foreground job stop and takes the terminal back.
func signalOrder(pid int, children []int, sig syscall.Signal) []int {
	order := append(slices.Clone(children), pid)
	if sig == syscall.SIGSTOP {
		slices.Reverse(order)
	}
	return order
}

func helperNice(p map[string]any) (int, error) {
	nice, err := params.Int(p, "nice")
	if err != nil || nice < -20 || nice > 19 {
		return 0, errors.New("invalid nice")
	}
	return nice, nil
}

// setNice sets pid's main thread, then its other threads on a best-effort basis since they can exit mid-way.
func setNice(pid, nice int) error {
	if err := syscall.Setpriority(syscall.PRIO_PROCESS, pid, nice); err != nil {
		return err
	}
	tasks, _ := os.ReadDir("/proc/" + strconv.Itoa(pid) + "/task")
	for _, t := range tasks {
		if tid, err := strconv.Atoi(t.Name()); err == nil && tid != pid {
			_ = syscall.Setpriority(syscall.PRIO_PROCESS, tid, nice)
		}
	}
	return nil
}

// descendants lists pid's descendants children first. A child that keep rejects ends its branch.
func descendants(pid int, parents map[int]int, keep func(int) bool) []int {
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
			if seen[c] || !keep(c) {
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

// treeOrder lists pid's descendants children first. A child whose name is in skip keeps its whole subtree,
// and self (the helper, which must stay able to send CONT) is left out.
func treeOrder(pid int, parents map[int]int, comm func(int) string, skip []string, self int) []int {
	return descendants(pid, parents, func(c int) bool {
		return c != self && !slices.Contains(skip, strings.ToLower(comm(c)))
	})
}

// mergedChildren lists the descendants the process list folds into pid's row: a chain of children
// running the same executable as pid.
func mergedChildren(pid int, parents map[int]int, exe, comm func(int) string, skip []string) []int {
	root := exe(pid)
	if root == "" {
		return nil
	}
	return descendants(pid, parents, func(c int) bool {
		return exe(c) == root && !slices.Contains(skip, strings.ToLower(comm(c)))
	})
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

func readExe(pid int) string {
	link, _ := os.Readlink("/proc/" + strconv.Itoa(pid) + "/exe")
	return link
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
