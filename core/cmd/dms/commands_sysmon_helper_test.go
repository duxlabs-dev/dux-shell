package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTreeOrderChildrenFirstAndSkipsSubtrees(t *testing.T) {
	parents := map[int]int{10: 1, 11: 10, 12: 11, 13: 10, 14: 13, 20: 1}
	names := map[int]string{11: "bash", 12: "sleep", 13: "Hyprland", 14: "kitty"}
	order := treeOrder(10, parents, func(p int) string { return names[p] }, []string{"hyprland"})
	assert.Equal(t, []int{12, 11}, order)
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
	assert.NotPanics(t, func() { treeOrder(11, parents, func(int) string { return "" }, nil) })
}
