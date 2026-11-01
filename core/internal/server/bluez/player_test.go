package bluez

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidatePlayerSnapshot(t *testing.T) {
	tests := []struct {
		name     string
		snapshot PlayerSnapshot
		wantErr  string
	}{
		{name: "playing", snapshot: PlayerSnapshot{PlaybackStatus: "Playing"}},
		{name: "invalid status", snapshot: PlayerSnapshot{PlaybackStatus: "Buffering"}, wantErr: "invalid playbackStatus"},
		{name: "negative length", snapshot: PlayerSnapshot{PlaybackStatus: "Stopped", Length: -1}, wantErr: "length must be nonnegative"},
		{name: "negative position", snapshot: PlayerSnapshot{PlaybackStatus: "Stopped", Position: -1}, wantErr: "position must be nonnegative"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validatePlayerSnapshot(tt.snapshot)
			if tt.wantErr == "" {
				require.NoError(t, err)
				return
			}
			require.ErrorContains(t, err, tt.wantErr)
		})
	}
}

func TestPlayerProperties(t *testing.T) {
	snapshot := PlayerSnapshot{
		Enabled:        true,
		Identity:       "DMS Music",
		PlaybackStatus: "Playing",
		Title:          "Title",
		Artist:         "Artist",
		Album:          "Album",
		Length:         12_000_000,
		Position:       3_000_000,
		CanControl:     true,
		CanPlay:        true,
		CanPause:       true,
		CanGoNext:      true,
		CanGoPrevious:  false,
	}

	properties := playerProperties(snapshot)
	expectedSignatures := map[string]string{
		"PlaybackStatus": "s",
		"LoopStatus":     "s",
		"Rate":           "d",
		"Shuffle":        "b",
		"Metadata":       "a{sv}",
		"Volume":         "d",
		"Position":       "x",
		"MinimumRate":    "d",
		"MaximumRate":    "d",
		"Identity":       "s",
		"CanGoNext":      "b",
		"CanGoPrevious":  "b",
		"CanPlay":        "b",
		"CanPause":       "b",
		"CanSeek":        "b",
		"CanControl":     "b",
	}
	require.Len(t, properties, len(expectedSignatures))
	for name, signature := range expectedSignatures {
		assert.Equal(t, signature, properties[name].Signature().String(), name)
	}

	assert.Equal(t, "Playing", properties["PlaybackStatus"].Value())
	assert.Equal(t, "None", properties["LoopStatus"].Value())
	assert.Equal(t, 1.0, properties["Rate"].Value())
	assert.Equal(t, false, properties["Shuffle"].Value())
	assert.Equal(t, 1.0, properties["Volume"].Value())
	assert.Equal(t, int64(3_000_000), properties["Position"].Value())
	assert.Equal(t, 1.0, properties["MinimumRate"].Value())
	assert.Equal(t, 1.0, properties["MaximumRate"].Value())
	assert.Equal(t, "DMS Music", properties["Identity"].Value())
	assert.Equal(t, false, properties["CanSeek"].Value())
	assert.Equal(t, true, properties["CanControl"].Value())
	assert.Equal(t, false, properties["CanGoPrevious"].Value())

	metadata, ok := properties["Metadata"].Value().(map[string]dbus.Variant)
	require.True(t, ok)
	trackID, ok := metadata["mpris:trackid"].Value().(dbus.ObjectPath)
	require.True(t, ok)
	assert.True(t, trackID.IsValid())
	assert.NotEqual(t, dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack"), trackID)
	assert.Equal(t, "Title", metadata["xesam:title"].Value())
	assert.Equal(t, []string{"Artist"}, metadata["xesam:artist"].Value())
	assert.Equal(t, "Album", metadata["xesam:album"].Value())
	assert.Equal(t, int64(12_000_000), metadata["mpris:length"].Value())
}

func TestChangedPlayerPropertiesExcludesPosition(t *testing.T) {
	old := PlayerSnapshot{Enabled: true, PlaybackStatus: "Paused", Position: 1_000_000}
	current := old
	current.Position = 2_000_000

	assert.Empty(t, changedPlayerProperties(old, current))

	current.PlaybackStatus = "Playing"
	changed := changedPlayerProperties(old, current)
	assert.NotContains(t, changed, "Position")
	assert.Equal(t, "Playing", changed["PlaybackStatus"].Value())
}

func TestPlayerTrackIDIsStableAndMetadataDependent(t *testing.T) {
	snapshot := PlayerSnapshot{Enabled: true, Title: "Title", Artist: "Artist", Album: "Album", Length: 42}
	trackID := playerTrackID(snapshot)
	assert.Equal(t, trackID, playerTrackID(snapshot))

	snapshot.Title = "Other Title"
	assert.NotEqual(t, trackID, playerTrackID(snapshot))
	assert.True(t, playerTrackID(snapshot).IsValid())
}

func TestStalePlayerPropertiesClearMetadataAndCapabilities(t *testing.T) {
	old := PlayerSnapshot{
		Enabled:        true,
		Identity:       "Dux Shell",
		PlaybackStatus: "Playing",
		Title:          "Title",
		Artist:         "Artist",
		Album:          "Album",
		Length:         10_000_000,
		Position:       2_000_000,
		CanControl:     true,
		CanPlay:        true,
		CanPause:       true,
		CanGoNext:      true,
		CanGoPrevious:  true,
	}

	changed := changedPlayerProperties(old, stalePlayerSnapshot(old))

	assert.Equal(t, "Stopped", changed["PlaybackStatus"].Value())
	assert.Equal(t, false, changed["CanControl"].Value())
	assert.Equal(t, false, changed["CanPlay"].Value())
	assert.Equal(t, false, changed["CanPause"].Value())
	assert.Equal(t, false, changed["CanGoNext"].Value())
	assert.Equal(t, false, changed["CanGoPrevious"].Value())
	assert.NotContains(t, changed, "Position")
	metadata, ok := changed["Metadata"].Value().(map[string]dbus.Variant)
	require.True(t, ok)
	require.Len(t, metadata, 1)
	assert.Equal(t, dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack"), metadata["mpris:trackid"].Value())
}

func TestPlayerPropertiesDisabled(t *testing.T) {
	properties := playerProperties(PlayerSnapshot{
		PlaybackStatus: "Playing",
		Identity:       "ignored",
		Title:          "ignored",
		Position:       42,
		CanControl:     true,
		CanPlay:        true,
	})

	assert.Equal(t, "Stopped", properties["PlaybackStatus"].Value())
	assert.Equal(t, int64(0), properties["Position"].Value())
	assert.Equal(t, "", properties["Identity"].Value())
	assert.Equal(t, false, properties["CanControl"].Value())
	metadata, ok := properties["Metadata"].Value().(map[string]dbus.Variant)
	require.True(t, ok)
	require.Len(t, metadata, 1)
	assert.Equal(t, dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack"), metadata["mpris:trackid"].Value())
}

func TestPlayerWritablePropertiesReportNotSupported(t *testing.T) {
	properties := &mprisProperties{player: newMPRISPlayer(nil, nil)}
	for _, name := range []string{"LoopStatus", "Rate", "Shuffle", "Volume"} {
		dbusErr := properties.Set(mprisPlayerIface, name, dbus.MakeVariant(false))
		require.NotNil(t, dbusErr, name)
		assert.Equal(t, "org.freedesktop.DBus.Error.NotSupported", dbusErr.Name, name)
	}

	dbusErr := properties.Set(mprisPlayerIface, "Position", dbus.MakeVariant(int64(0)))
	require.NotNil(t, dbusErr)
	assert.Equal(t, "org.freedesktop.DBus.Error.PropertyReadOnly", dbusErr.Name)
}

func TestPlayerPublishNormalizesCapabilitiesWithoutControl(t *testing.T) {
	player := newMPRISPlayer(nil, nil)
	require.NoError(t, player.publish(PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Paused",
		CanPlay:        true,
		CanPause:       true,
		CanGoNext:      true,
		CanGoPrevious:  true,
	}, nil))

	snapshot := player.currentSnapshot()
	assert.False(t, snapshot.CanPlay)
	assert.False(t, snapshot.CanPause)
	assert.False(t, snapshot.CanGoNext)
	assert.False(t, snapshot.CanGoPrevious)
}

func TestPlayerCommandCapabilityGatingAndDispatch(t *testing.T) {
	manager := &Manager{}
	player := newMPRISPlayer(nil, manager.dispatchPlayerCommand)
	manager.mprisPlayer = player
	commands, err := manager.SubscribePlayerCommands("test")
	require.NoError(t, err)
	assert.NotEmpty(t, (<-commands).Lease)
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Playing",
		CanControl:     true,
		CanPlay:        true,
		CanPause:       false,
		CanGoNext:      true,
	}

	require.Nil(t, player.dispatchCommand("play"))
	assert.Equal(t, PlayerCommand{Command: "play"}, <-commands)
	require.Nil(t, player.dispatchCommand("next"))
	assert.Equal(t, PlayerCommand{Command: "next"}, <-commands)

	dbusErr := player.dispatchCommand("pause")
	require.NotNil(t, dbusErr)
	assert.Equal(t, "org.freedesktop.DBus.Error.NotSupported", dbusErr.Name)

	dbusErr = player.dispatchCommand("playPause")
	require.NotNil(t, dbusErr)
	assert.Empty(t, commands)
	manager.UnsubscribePlayerCommands("test")
}

func TestManagerPlayerCommandSubscription(t *testing.T) {
	manager := &Manager{}
	player := newMPRISPlayer(nil, manager.dispatchPlayerCommand)
	manager.mprisPlayer = player
	commands, err := manager.SubscribePlayerCommands("test")
	require.NoError(t, err)
	assert.NotEmpty(t, (<-commands).Lease)
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Stopped",
		CanControl:     true,
		CanPlay:        true,
	}

	require.Nil(t, player.dispatchCommand("play"))
	assert.Equal(t, PlayerCommand{Command: "play"}, <-commands)
	manager.UnsubscribePlayerCommands("test")
	_, open := <-commands
	assert.False(t, open)
}

func TestPlayerCommandFailsWithoutActiveOwner(t *testing.T) {
	manager := &Manager{}
	player := newMPRISPlayer(nil, manager.dispatchPlayerCommand)
	manager.mprisPlayer = player
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Stopped",
		CanControl:     true,
		CanPlay:        true,
	}

	dbusErr := player.dispatchCommand("play")
	require.NotNil(t, dbusErr)
	assert.Equal(t, "org.freedesktop.DBus.Error.Failed", dbusErr.Name)
}

func TestPlayerCommandFailsWhenOwnerQueueIsFull(t *testing.T) {
	manager := &Manager{}
	player := newMPRISPlayer(nil, manager.dispatchPlayerCommand)
	manager.mprisPlayer = player
	commands, err := manager.SubscribePlayerCommands("test")
	require.NoError(t, err)
	assert.NotEmpty(t, (<-commands).Lease)
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Stopped",
		CanControl:     true,
		CanPlay:        true,
	}

	for range cap(commands) {
		require.Nil(t, player.dispatchCommand("play"))
	}
	dbusErr := player.dispatchCommand("play")
	require.NotNil(t, dbusErr)
	assert.Equal(t, "org.freedesktop.DBus.Error.Failed", dbusErr.Name)
	manager.UnsubscribePlayerCommands("test")
}

func TestDuplicatePlayerCommandSubscriberIsRejected(t *testing.T) {
	manager := &Manager{}
	commands, err := manager.SubscribePlayerCommands("duplicate")
	require.NoError(t, err)
	assert.NotEmpty(t, (<-commands).Lease)

	duplicate, err := manager.SubscribePlayerCommands("duplicate")
	require.ErrorContains(t, err, "already exists")
	assert.Nil(t, duplicate)

	manager.UnsubscribePlayerCommands("duplicate")
}

func TestManagerPlayerCommandLeaseControlsPublication(t *testing.T) {
	player := newMPRISPlayer(nil, nil)
	manager := &Manager{mprisPlayer: player}
	commands, err := manager.SubscribePlayerCommands("first")
	require.NoError(t, err)
	lease := (<-commands).Lease
	assert.NotEmpty(t, lease)
	second, err := manager.SubscribePlayerCommands("second")
	require.NoError(t, err)
	select {
	case event := <-second:
		t.Fatalf("waiting subscriber received unexpected event: %#v", event)
	default:
	}

	snapshot := PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Stopped",
		CanControl:     true,
		CanPlay:        true,
	}
	require.Error(t, manager.PublishMPRIS("wrong-lease", snapshot))
	require.NoError(t, manager.PublishMPRIS(lease, snapshot))
	require.Nil(t, manager.dispatchPlayerCommand(PlayerCommand{Command: "play"}))
	assert.Equal(t, PlayerCommand{Command: "play"}, <-commands)

	manager.UnsubscribePlayerCommands("first")
	require.Error(t, manager.PublishMPRIS(lease, snapshot))
	replacementLease := (<-second).Lease
	assert.NotEmpty(t, replacementLease)
	require.NoError(t, manager.PublishMPRIS(replacementLease, snapshot))
	manager.UnsubscribePlayerCommands("second")
}

func TestDisconnectedPlayerCommandWaiterIsRemoved(t *testing.T) {
	manager := &Manager{}
	first, err := manager.SubscribePlayerCommands("first")
	require.NoError(t, err)
	assert.NotEmpty(t, (<-first).Lease)
	waiting, err := manager.SubscribePlayerCommands("waiting")
	require.NoError(t, err)

	manager.UnsubscribePlayerCommands("waiting")
	_, open := <-waiting
	assert.False(t, open)
	assert.Empty(t, manager.commandWaiters)

	third, err := manager.SubscribePlayerCommands("third")
	require.NoError(t, err)
	manager.UnsubscribePlayerCommands("first")
	assert.NotEmpty(t, (<-third).Lease)
	manager.UnsubscribePlayerCommands("third")
}

func TestPlayerCommandOwnerLossWithoutWaiterDisablesPlayer(t *testing.T) {
	player := newMPRISPlayer(nil, nil)
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		Identity:       "Dux Shell",
		PlaybackStatus: "Playing",
		Title:          "Title",
		CanControl:     true,
		CanPlay:        true,
	}
	manager := &Manager{mprisPlayer: player}
	owner, err := manager.SubscribePlayerCommands("owner")
	require.NoError(t, err)
	ownerLease := (<-owner).Lease
	require.NotEmpty(t, ownerLease)

	manager.UnsubscribePlayerCommands("owner")

	assert.Equal(t, disabledPlayerSnapshot(), player.currentSnapshot())
	require.Error(t, manager.PublishMPRIS(ownerLease, PlayerSnapshot{Enabled: true}))
}

func TestPlayerCommandOwnerLossClearsStaleStateAndPromotesWaiter(t *testing.T) {
	player := newMPRISPlayer(nil, nil)
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		Identity:       "Dux Shell",
		PlaybackStatus: "Playing",
		Title:          "Title",
		Artist:         "Artist",
		Album:          "Album",
		Length:         10_000_000,
		Position:       2_000_000,
		CanControl:     true,
		CanPlay:        true,
		CanPause:       true,
		CanGoNext:      true,
		CanGoPrevious:  true,
	}
	manager := &Manager{mprisPlayer: player}
	owner, err := manager.SubscribePlayerCommands("owner")
	require.NoError(t, err)
	ownerLease := (<-owner).Lease
	require.NotEmpty(t, ownerLease)
	waiter, err := manager.SubscribePlayerCommands("waiter")
	require.NoError(t, err)

	manager.UnsubscribePlayerCommands("owner")
	assert.Equal(t, PlayerSnapshot{
		Enabled:        true,
		Identity:       "Dux Shell",
		PlaybackStatus: "Stopped",
	}, player.currentSnapshot())
	waiterLease := (<-waiter).Lease
	require.NotEmpty(t, waiterLease)
	assert.NotEqual(t, ownerLease, waiterLease)
	require.Error(t, manager.PublishMPRIS(ownerLease, PlayerSnapshot{Enabled: true}))
	require.NoError(t, manager.PublishMPRIS(waiterLease, PlayerSnapshot{Enabled: true, PlaybackStatus: "Stopped"}))

	manager.UnsubscribePlayerCommands("waiter")
}

func TestPlayerPlayPauseDispatchesWhenPaused(t *testing.T) {
	manager := &Manager{}
	player := newMPRISPlayer(nil, manager.dispatchPlayerCommand)
	manager.mprisPlayer = player
	commands, err := manager.SubscribePlayerCommands("test")
	require.NoError(t, err)
	assert.NotEmpty(t, (<-commands).Lease)
	player.snapshot = PlayerSnapshot{
		Enabled:        true,
		PlaybackStatus: "Paused",
		CanControl:     true,
		CanPlay:        true,
	}

	require.Nil(t, player.dispatchCommand("playPause"))
	assert.Equal(t, PlayerCommand{Command: "playPause"}, <-commands)
	manager.UnsubscribePlayerCommands("test")
}

func TestBluezOwnerChangedClearsAndRefreshesOnReplacement(t *testing.T) {
	player := newMPRISPlayer(nil, nil)
	player.registered["/org/bluez/hci0"] = struct{}{}
	manager := &Manager{
		mprisPlayer:    player,
		adapterRefresh: make(chan struct{}, 1),
	}

	manager.handleBluezOwnerChanged(&dbus.Signal{
		Name: dbusIface + ".NameOwnerChanged",
		Body: []any{bluezService, ":1.10", ":1.11"},
	})

	assert.Empty(t, player.registered)
	assert.Len(t, manager.adapterRefresh, 1)
}

func TestBluezOwnerChangedRefreshCoalescesWithoutDropping(t *testing.T) {
	manager := &Manager{adapterRefresh: make(chan struct{}, 1)}
	signal := &dbus.Signal{
		Name: dbusIface + ".NameOwnerChanged",
		Body: []any{bluezService, "", ":1.11"},
	}

	manager.handleBluezOwnerChanged(signal)
	manager.handleBluezOwnerChanged(signal)

	assert.Len(t, manager.adapterRefresh, 1)
}

func TestBluezOwnerChangedClearsOnLossWithoutRefresh(t *testing.T) {
	player := newMPRISPlayer(nil, nil)
	player.registered["/org/bluez/hci0"] = struct{}{}
	manager := &Manager{
		mprisPlayer:    player,
		adapterRefresh: make(chan struct{}, 1),
	}

	manager.handleBluezOwnerChanged(&dbus.Signal{
		Name: dbusIface + ".NameOwnerChanged",
		Body: []any{bluezService, ":1.10", ""},
	})

	assert.Empty(t, player.registered)
	assert.Empty(t, manager.adapterRefresh)
}

func TestRegistrationChanges(t *testing.T) {
	registered := map[dbus.ObjectPath]struct{}{
		"/org/bluez/hci0": {},
		"/org/bluez/hci2": {},
	}

	add, remove := registrationChanges(registered, []dbus.ObjectPath{"/org/bluez/hci0", "/org/bluez/hci1"}, true)
	assert.Equal(t, []dbus.ObjectPath{"/org/bluez/hci1"}, add)
	assert.Equal(t, []dbus.ObjectPath{"/org/bluez/hci2"}, remove)

	add, remove = registrationChanges(registered, []dbus.ObjectPath{"/org/bluez/hci0"}, false)
	assert.Empty(t, add)
	assert.Equal(t, []dbus.ObjectPath{"/org/bluez/hci0", "/org/bluez/hci2"}, remove)
}

func TestPlayerSnapshotFromParamsRequiresCompleteIntegralSnapshot(t *testing.T) {
	params := map[string]any{
		"enabled":        true,
		"identity":       "DMS",
		"playbackStatus": "Paused",
		"title":          "Title",
		"artist":         "Artist",
		"album":          "Album",
		"length":         float64(10_000_000),
		"position":       float64(1_000_000),
		"canControl":     true,
		"canPlay":        true,
		"canPause":       true,
		"canGoNext":      false,
		"canGoPrevious":  false,
	}

	snapshot, err := playerSnapshotFromParams(params)
	require.NoError(t, err)
	assert.Equal(t, int64(10_000_000), snapshot.Length)
	assert.Equal(t, int64(1_000_000), snapshot.Position)

	delete(params, "album")
	_, err = playerSnapshotFromParams(params)
	require.ErrorContains(t, err, "album")
	params["album"] = "Album"
	params["position"] = 1.5
	_, err = playerSnapshotFromParams(params)
	require.ErrorContains(t, err, "position")
}
