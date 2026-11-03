package screenshot

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"regexp"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func aqueousSnapshot(ctx context.Context) (aqueousSnapshotModel, error) {
	executable, err := os.Executable()
	if err != nil {
		return aqueousSnapshotModel{}, err
	}
	var data json.RawMessage
	if err := utils.RunJSON(ctx, executable, []string{"ipc", "call", "aqueous", "snapshot", os.Getenv("AQUEOUS_SOCKET")}, nil, &data); err != nil {
		return aqueousSnapshotModel{}, fmt.Errorf("get Aqueous state from DMS; a shell must be running in this session: %w", err)
	}
	return parseAqueousSnapshot(data)
}

type aqueousBox struct {
	X, Y, Width, Height int64
}

func (b aqueousBox) valid() bool {
	for _, value := range []int64{b.X, b.Y, b.Width, b.Height} {
		if value < math.MinInt32 || value > math.MaxInt32 {
			return false
		}
	}
	return true
}

type aqueousCaptureEntity struct {
	Kind          string      `json:"kind"`
	ID            string      `json:"id"`
	Name          string      `json:"name"`
	Output        string      `json:"output"`
	Window        string      `json:"window"`
	FocusKind     string      `json:"focus_kind"`
	Visible       bool        `json:"visible"`
	Minimized     bool        `json:"minimized"`
	CanActivate   bool        `json:"can_activate"`
	Enabled       bool        `json:"enabled"`
	Powered       bool        `json:"powered"`
	Scale         float64     `json:"scale"`
	Bounds        *aqueousBox `json:"bounds"`
	OuterGeometry *aqueousBox `json:"outer_geometry"`
}

type aqueousSnapshotModel struct {
	Entities map[string]*aqueousCaptureEntity
}

func (m aqueousSnapshotModel) Seat(name string) (*aqueousCaptureEntity, error) {
	if name != "" {
		if seat := m.Entities["seat:"+name]; seat != nil {
			return seat, nil
		}
		return nil, errors.New("not_found: seat")
	}
	var seat *aqueousCaptureEntity
	for _, entity := range m.Entities {
		if entity.Kind != "seat" {
			continue
		}
		if seat != nil {
			return nil, errors.New("ambiguous_seat")
		}
		seat = entity
	}
	if seat == nil {
		return nil, errors.New("unavailable: no seat")
	}
	return seat, nil
}

func parseAqueousSnapshot(data []byte) (aqueousSnapshotModel, error) {
	var batch struct {
		Error        string                 `json:"error"`
		Schema       int                    `json:"schema"`
		Session      string                 `json:"session"`
		Sequence     string                 `json:"sequence"`
		BaseSequence json.RawMessage        `json:"base_sequence"`
		Type         string                 `json:"type"`
		Upsert       []aqueousCaptureEntity `json:"upsert"`
		Removed      []string               `json:"removed"`
	}
	var model aqueousSnapshotModel
	if err := utils.DecodeJSON(data, &batch); err != nil {
		return model, err
	}
	if batch.Error != "" {
		return model, errors.New("aqueous state is unavailable in the running DMS shell")
	}
	if batch.Schema != 1 || batch.Type != "snapshot" || !bytes.Equal(batch.BaseSequence, []byte("null")) || batch.Upsert == nil || batch.Removed == nil || len(batch.Removed) != 0 || !regexp.MustCompile(`^[0-9a-f]{32}$`).MatchString(batch.Session) || !regexp.MustCompile(`^[0-9]+$`).MatchString(batch.Sequence) {
		return model, errors.New("invalid Aqueous shell snapshot")
	}
	model.Entities = make(map[string]*aqueousCaptureEntity, len(batch.Upsert))
	for i := range batch.Upsert {
		entity := &batch.Upsert[i]
		key := entity.Kind + ":" + entity.ID
		if entity.ID == "" || entity.Kind == "" || model.Entities[key] != nil {
			return aqueousSnapshotModel{}, errors.New("invalid or duplicate shell entity")
		}
		model.Entities[key] = entity
	}
	if model.Entities["session:session"] == nil {
		return aqueousSnapshotModel{}, errors.New("missing session entity")
	}
	return model, nil
}
