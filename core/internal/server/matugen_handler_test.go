package server

import (
	"encoding/json"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMatugenQueueOptionsIconTiles(t *testing.T) {
	opts := matugenQueueOptions(ipc.Request{Params: map[string]any{}})
	assert.Equal(t, "", opts.IconTileColor)
	assert.Equal(t, "", opts.IconColorSource)
	assert.Equal(t, "", opts.IconTileStyle)
	assert.Equal(t, -1, opts.IconTileTone, "a client that sends no tone keeps the theme's")
	assert.Equal(t, -1, opts.IconOwnTone)
	assert.Equal(t, "", opts.IconFileStyle, "a client that sends no file style gets the standard one")
	assert.Equal(t, "", opts.IconAppStyle, "a client that sends no app style gets the color one")

	// Params arrive as JSON, so numbers are float64.
	var req ipc.Request
	require.NoError(t, json.Unmarshal([]byte(`{"method":"matugen.queue","params":{
		"iconGradient":true,"iconTileColor":"ring","iconColorSource":"common","iconTileStyle":"neutral",
		"iconTileTone":0,"iconOwnTone":42,"iconFileStyle":"color","iconAppStyle":"themed"}}`), &req))
	opts = matugenQueueOptions(req)
	assert.True(t, opts.IconGradient)
	assert.Equal(t, "ring", opts.IconTileColor)
	assert.Equal(t, "common", opts.IconColorSource)
	assert.Equal(t, "neutral", opts.IconTileStyle)
	assert.Equal(t, 0, opts.IconTileTone)
	assert.Equal(t, 42, opts.IconOwnTone)
	assert.Equal(t, "color", opts.IconFileStyle)
	assert.Equal(t, "themed", opts.IconAppStyle)
}
