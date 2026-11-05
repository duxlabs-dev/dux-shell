package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"slices"
	"strings"
	"syscall"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTreeOrderChildrenFirstAndSkipsSubtrees(t *testing.T) {
	parents := map[int]int{10: 1, 11: 10, 12: 11, 13: 10, 14: 13, 20: 1}
	names := map[int]string{11: "bash", 12: "sleep", 13: "Hyprland", 14: "kitty"}
	order := treeOrder(10, parents, func(p int) string { return names[p] }, []string{"hyprland"}, 0)
	assert.Equal(t, []int{12, 11}, order)
	assert.Equal(t, []int{11}, treeOrder(10, parents, func(p int) string { return names[p] }, []string{"hyprland"}, 12))
}

func TestHelperPidRejectsInit(t *testing.T) {
	_, err := helperPid(map[string]any{"pid": float64(1)})
	assert.Error(t, err)
	_, err = helperPid(map[string]any{})
	assert.Error(t, err)
	pid, err := helperPid(map[string]any{"pid": float64(4242)})
	require.NoError(t, err)
	assert.Equal(t, 4242, pid)
}

func TestSysmonHelperCallRejectsUnknownAndNonServices(t *testing.T) {
	_, err := sysmonHelperCall("shell.exec", map[string]any{"cmd": "id"})
	assert.Error(t, err)
	_, err = sysmonHelperCall("process.restartService", map[string]any{"pid": float64(4242), "unit": "app-x.scope"})
	assert.Error(t, err)
	_, err = sysmonHelperCall("drives.smart", map[string]any{"device": "/etc/shadow"})
	assert.Error(t, err)
}

func TestServeSysmonHelperAnswersEachLine(t *testing.T) {
	in := strings.NewReader("{\"id\":1,\"method\":\"ok\"}\nnot json\n{\"id\":2,\"method\":\"bad\"}\n")
	var out bytes.Buffer
	serveSysmonHelper(in, &out, func(method string, _ map[string]any) (any, error) {
		if method == "ok" {
			return 7, nil
		}
		return nil, errors.New("nope")
	})
	got := map[float64]map[string]any{}
	for _, line := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		var m map[string]any
		require.NoError(t, json.Unmarshal([]byte(line), &m))
		got[m["id"].(float64)] = m
	}
	assert.Equal(t, float64(7), got[1]["result"])
	assert.Equal(t, "nope", got[2]["error"])
}

func TestIsRootHelper(t *testing.T) {
	assert.True(t, isRootHelper([]string{"dms", "sysmon-helper"}))
	assert.False(t, isRootHelper([]string{"dms", "run"}))
	assert.False(t, isRootHelper([]string{"dms", "ipc", "sysmon-helper"}))
	assert.False(t, isRootHelper([]string{"dms"}))
}

func TestTreeOrderSurvivesParentCycle(t *testing.T) {
	parents := map[int]int{11: 12, 12: 11}
	assert.NotPanics(t, func() { treeOrder(11, parents, func(int) string { return "" }, nil, 0) })
}

func TestHelperPidSignal(t *testing.T) {
	for name, want := range map[string]syscall.Signal{"": syscall.SIGTERM, "TERM": syscall.SIGTERM, "KILL": syscall.SIGKILL, "STOP": syscall.SIGSTOP, "CONT": syscall.SIGCONT} {
		p := map[string]any{"pid": float64(4242)}
		if name != "" {
			p["signal"] = name
		}
		_, sig, err := helperPidSignal(p)
		require.NoError(t, err, name)
		assert.Equal(t, want, sig, name)
	}
	for _, name := range []any{"HUP", "term", "", float64(19)} {
		_, _, err := helperPidSignal(map[string]any{"pid": float64(4242), "signal": name})
		assert.Error(t, err, name)
	}
	_, _, err := helperPidSignal(map[string]any{"pid": float64(os.Getpid()), "signal": "STOP"})
	assert.Error(t, err)
	_, _, err = helperPidSignal(map[string]any{"pid": float64(os.Getpid()), "signal": "CONT"})
	assert.NoError(t, err)
}

func TestSignalOrder(t *testing.T) {
	parents := map[int]int{11: 10, 12: 11, 13: 10}
	children := treeOrder(10, parents, func(int) string { return "" }, nil, 0)
	before := func(order []int, first, second int) bool {
		return slices.Index(order, first) < slices.Index(order, second)
	}
	for _, sig := range []syscall.Signal{syscall.SIGTERM, syscall.SIGKILL, syscall.SIGCONT, syscall.SIGSTOP} {
		order := signalOrder(10, children, sig)
		assert.ElementsMatch(t, []int{10, 11, 12, 13}, order, sig)
		parentsFirst := sig == syscall.SIGSTOP
		for child, parent := range parents {
			assert.Equal(t, parentsFirst, before(order, parent, child), "%v: %d and %d", sig, parent, child)
		}
	}
}

func TestHelperNice(t *testing.T) {
	for _, n := range []float64{-20, 19} {
		_, err := helperNice(map[string]any{"nice": n})
		assert.NoError(t, err, n)
	}
	for _, p := range []map[string]any{{"nice": float64(-21)}, {"nice": float64(20)}, {}, {"nice": "5"}} {
		_, err := helperNice(p)
		assert.Error(t, err, p)
	}
}

func TestMergedChildren(t *testing.T) {
	// 12 runs another exe, so its same-exe child 13 is its own row; 14 has no readable exe.
	parents := map[int]int{11: 10, 12: 10, 13: 12, 14: 10, 15: 11, 30: 1, 16: 14}
	exes := map[int]string{10: "/bin/bash", 11: "/bin/bash", 12: "/bin/python", 13: "/bin/bash", 15: "/bin/bash", 30: "/bin/bash"}
	comms := map[int]string{15: "Sleeper"}
	exe := func(p int) string { return exes[p] }
	comm := func(p int) string { return comms[p] }

	assert.ElementsMatch(t, []int{11, 15}, mergedChildren(10, parents, exe, comm, nil))
	assert.Equal(t, []int{11}, mergedChildren(10, parents, exe, comm, []string{"sleeper"}))
	assert.Nil(t, mergedChildren(14, parents, exe, comm, nil), "empty root exe")
}
