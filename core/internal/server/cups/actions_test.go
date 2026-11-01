package cups

import (
	"errors"
	"testing"
	"time"

	mocks_cups "github.com/duxlabs-dev/dux-shell/core/internal/mocks/cups"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestManager_GetPrinters(t *testing.T) {
	tests := []struct {
		name    string
		mockRet map[string]ipp.Attributes
		mockErr error
		want    int
		wantErr bool
	}{
		{
			name: "success",
			mockRet: map[string]ipp.Attributes{
				"printer1": {
					ipp.AttributePrinterName:            []ipp.Attribute{{Value: "printer1"}},
					ipp.AttributePrinterUriSupported:    []ipp.Attribute{{Value: "ipp://localhost/printers/printer1"}},
					ipp.AttributePrinterState:           []ipp.Attribute{{Value: 3}},
					ipp.AttributePrinterStateReasons:    []ipp.Attribute{{Value: "none"}},
					ipp.AttributePrinterLocation:        []ipp.Attribute{{Value: "Office"}},
					ipp.AttributePrinterInfo:            []ipp.Attribute{{Value: "Test Printer"}},
					ipp.AttributePrinterMakeAndModel:    []ipp.Attribute{{Value: "Generic"}},
					ipp.AttributePrinterIsAcceptingJobs: []ipp.Attribute{{Value: true}},
				},
			},
			mockErr: nil,
			want:    1,
			wantErr: false,
		},
		{
			name:    "error",
			mockRet: nil,
			mockErr: errors.New("test error"),
			want:    0,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := mocks_cups.NewMockCUPSClientInterface(t)
			mockClient.EXPECT().GetPrinters(mock.Anything).Return(tt.mockRet, tt.mockErr)

			m := &Manager{
				client: mockClient,
			}

			got, err := m.GetPrinters()
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.want, len(got))
				if len(got) > 0 {
					assert.Equal(t, "printer1", got[0].Name)
					assert.Equal(t, "idle", got[0].State)
					assert.Equal(t, "Office", got[0].Location)
					assert.True(t, got[0].Accepting)
				}
			}
		})
	}
}

func TestManager_GetJobs(t *testing.T) {
	tests := []struct {
		name    string
		mockRet map[int]ipp.Attributes
		mockErr error
		want    int
		wantErr bool
	}{
		{
			name: "success",
			mockRet: map[int]ipp.Attributes{
				1: {
					ipp.AttributeJobID:                  []ipp.Attribute{{Value: 1}},
					ipp.AttributeJobName:                []ipp.Attribute{{Value: "test-job"}},
					ipp.AttributeJobState:               []ipp.Attribute{{Value: 5}},
					ipp.AttributeJobPrinterURI:          []ipp.Attribute{{Value: "ipp://localhost/printers/printer1"}},
					ipp.AttributeJobOriginatingUserName: []ipp.Attribute{{Value: "testuser"}},
					ipp.AttributeJobKilobyteOctets:      []ipp.Attribute{{Value: 10}},
					"time-at-creation":                  []ipp.Attribute{{Value: 1609459200}},
				},
			},
			mockErr: nil,
			want:    1,
			wantErr: false,
		},
		{
			name:    "error",
			mockRet: nil,
			mockErr: errors.New("test error"),
			want:    0,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := mocks_cups.NewMockCUPSClientInterface(t)
			mockClient.EXPECT().GetJobs("printer1", "", "not-completed", false, 0, 0, mock.Anything).
				Return(tt.mockRet, tt.mockErr)

			m := &Manager{
				client: mockClient,
			}

			got, err := m.GetJobs("printer1", "not-completed")
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.want, len(got))
				if len(got) > 0 {
					assert.Equal(t, 1, got[0].ID)
					assert.Equal(t, "test-job", got[0].Name)
					assert.Equal(t, "processing", got[0].State)
					assert.Equal(t, "testuser", got[0].User)
					assert.Equal(t, "printer1", got[0].Printer)
					assert.Equal(t, 10240, got[0].Size)
					assert.Equal(t, time.Unix(1609459200, 0), got[0].TimeCreated)
				}
			}
		})
	}
}

func TestManager_GetDevices(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetDevices().Return(map[string]ipp.Attributes{
		"usb://HP/LaserJet": {
			"device-class":          []ipp.Attribute{{Value: "direct"}},
			"device-info":           []ipp.Attribute{{Value: "HP LaserJet"}},
			"device-make-and-model": []ipp.Attribute{{Value: "HP LaserJet 1020"}},
		},
	}, nil)

	m := &Manager{client: mockClient}
	got, err := m.GetDevices()
	assert.NoError(t, err)
	assert.Len(t, got, 1)
	assert.Equal(t, "usb://HP/LaserJet", got[0].URI)
	assert.Equal(t, "direct", got[0].Class)
}

func TestManager_GetPPDs(t *testing.T) {
	tests := []struct {
		name    string
		mockRet map[string]ipp.Attributes
		mockErr error
		want    int
		wantErr bool
	}{
		{
			name: "success",
			mockRet: map[string]ipp.Attributes{
				"drv:///sample.drv/generic.ppd": {
					"ppd-make-and-model": []ipp.Attribute{{Value: "Generic PostScript"}},
					"ppd-type":           []ipp.Attribute{{Value: "ppd"}},
				},
			},
			mockErr: nil,
			want:    1,
			wantErr: false,
		},
		{
			name:    "error",
			mockRet: nil,
			mockErr: errors.New("test error"),
			want:    0,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := mocks_cups.NewMockCUPSClientInterface(t)
			mockClient.EXPECT().GetPPDs().Return(tt.mockRet, tt.mockErr)

			m := &Manager{client: mockClient}

			got, err := m.GetPPDs()
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			assert.NoError(t, err)
			assert.Equal(t, tt.want, len(got))
		})
	}
}

func TestManager_GetClasses(t *testing.T) {
	tests := []struct {
		name    string
		mockRet map[string]ipp.Attributes
		mockErr error
		want    int
		wantErr bool
	}{
		{
			name: "success",
			mockRet: map[string]ipp.Attributes{
				"office": {
					ipp.AttributePrinterName:  []ipp.Attribute{{Value: "office"}},
					ipp.AttributePrinterState: []ipp.Attribute{{Value: 3}},
					ipp.AttributeMemberNames:  []ipp.Attribute{{Value: "printer1"}, {Value: "printer2"}},
				},
			},
			mockErr: nil,
			want:    1,
			wantErr: false,
		},
		{
			name:    "error",
			mockRet: nil,
			mockErr: errors.New("test error"),
			want:    0,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := mocks_cups.NewMockCUPSClientInterface(t)
			mockClient.EXPECT().GetClasses(mock.Anything).Return(tt.mockRet, tt.mockErr)

			m := &Manager{client: mockClient}

			got, err := m.GetClasses()
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			assert.NoError(t, err)
			assert.Equal(t, tt.want, len(got))
			if len(got) > 0 {
				assert.Equal(t, "office", got[0].Name)
				assert.Equal(t, 2, len(got[0].Members))
			}
		})
	}
}
