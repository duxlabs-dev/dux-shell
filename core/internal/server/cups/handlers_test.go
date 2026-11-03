package cups

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	mocks_cups "github.com/duxlabs-dev/dux-shell/core/internal/mocks/cups"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

type mockConn struct {
	*bytes.Buffer
}

func (m *mockConn) Close() error                       { return nil }
func (m *mockConn) LocalAddr() net.Addr                { return nil }
func (m *mockConn) RemoteAddr() net.Addr               { return nil }
func (m *mockConn) SetDeadline(t time.Time) error      { return nil }
func (m *mockConn) SetReadDeadline(t time.Time) error  { return nil }
func (m *mockConn) SetWriteDeadline(t time.Time) error { return nil }

func TestHandleGetPrinters(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{
		"printer1": {
			ipp.AttributePrinterName:         []ipp.Attribute{{Value: "printer1"}},
			ipp.AttributePrinterState:        []ipp.Attribute{{Value: 3}},
			ipp.AttributePrinterUriSupported: []ipp.Attribute{{Value: "ipp://localhost/printers/printer1"}},
		},
	}, nil)

	m := &Manager{
		client: mockClient,
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.getPrinters",
	}

	handleGetPrinters(conn, req, m)

	var resp ipc.Response[[]Printer]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.Equal(t, 1, len(*resp.Result))
}

func TestHandleGetPrinters_Error(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(nil, errors.New("test error"))

	m := &Manager{
		client: mockClient,
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.getPrinters",
	}

	handleGetPrinters(conn, req, m)

	var resp ipc.Response[any]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.Nil(t, resp.Result)
	assert.NotNil(t, resp.Error)
}

func TestHandleGetJobs(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetJobs("printer1", "", "not-completed", false, 0, 0, mock.Anything).
		Return(map[int]ipp.Attributes{
			1: {
				ipp.AttributeJobID:    []ipp.Attribute{{Value: 1}},
				ipp.AttributeJobName:  []ipp.Attribute{{Value: "job1"}},
				ipp.AttributeJobState: []ipp.Attribute{{Value: 5}},
			},
		}, nil)

	m := &Manager{
		client: mockClient,
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.getJobs",
		Params: map[string]any{
			"printerName": "printer1",
		},
	}

	handleGetJobs(conn, req, m)

	var resp ipc.Response[[]Job]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.Equal(t, 1, len(*resp.Result))
}

func TestHandleGetJobs_MissingParam(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)

	m := &Manager{
		client: mockClient,
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.getJobs",
		Params: map[string]any{},
	}

	handleGetJobs(conn, req, m)

	var resp ipc.Response[any]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.Nil(t, resp.Result)
	assert.NotNil(t, resp.Error)
}

func TestHandlePausePrinter(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().PausePrinter("printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.pausePrinter",
		Params: map[string]any{
			"printerName": "printer1",
		},
	}

	handlePausePrinter(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleResumePrinter(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().ResumePrinter("printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.resumePrinter",
		Params: map[string]any{
			"printerName": "printer1",
		},
	}

	handleResumePrinter(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleCancelJob(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().CancelJob(1, false).Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.cancelJob",
		Params: map[string]any{
			"jobID": float64(1),
		},
	}

	handleCancelJob(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandlePurgeJobs(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().CancelAllJob("printer1", true).Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.purgeJobs",
		Params: map[string]any{
			"printerName": "printer1",
		},
	}

	handlePurgeJobs(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleRequest_UnknownMethod(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)

	m := &Manager{
		client: mockClient,
	}

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.unknownMethod",
	}

	HandleRequest(conn, req, m)

	var resp ipc.Response[any]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.Nil(t, resp.Result)
	assert.NotNil(t, resp.Error)
}

func TestHandleGetDevices(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetDevices().Return(map[string]ipp.Attributes{
		"usb://HP/LaserJet": {
			"device-class": []ipp.Attribute{{Value: "direct"}},
			"device-info":  []ipp.Attribute{{Value: "HP LaserJet"}},
		},
	}, nil)

	m := &Manager{client: mockClient}
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "cups.getDevices"}
	handleGetDevices(conn, req, m)

	var resp ipc.Response[[]Device]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.Equal(t, 1, len(*resp.Result))
}

func TestHandleGetPPDs(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetPPDs().Return(map[string]ipp.Attributes{
		"generic.ppd": {
			"ppd-make-and-model": []ipp.Attribute{{Value: "Generic"}},
		},
	}, nil)

	m := &Manager{client: mockClient}
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "cups.getPPDs"}
	handleGetPPDs(conn, req, m)

	var resp ipc.Response[[]PPD]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.Equal(t, 1, len(*resp.Result))
}

func TestHandleGetClasses(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().GetClasses(mock.Anything).Return(map[string]ipp.Attributes{
		"office": {
			ipp.AttributePrinterName:  []ipp.Attribute{{Value: "office"}},
			ipp.AttributePrinterState: []ipp.Attribute{{Value: 3}},
		},
	}, nil)

	m := &Manager{client: mockClient}
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "cups.getClasses"}
	handleGetClasses(conn, req, m)

	var resp ipc.Response[[]PrinterClass]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.Equal(t, 1, len(*resp.Result))
}

func TestHandleCreatePrinter(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().CreatePrinter("newprinter", "usb://HP", "generic.ppd", false, "", "", "").Return(nil)
	mockClient.EXPECT().ResumePrinter("newprinter").Return(nil)
	mockClient.EXPECT().AcceptJobs("newprinter").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.createPrinter",
		Params: map[string]any{
			"name":      "newprinter",
			"deviceURI": "usb://HP",
			"ppd":       "generic.ppd",
		},
	}
	handleCreatePrinter(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleCreatePrinter_MissingParams(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	m := &Manager{client: mockClient}
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "cups.createPrinter", Params: map[string]any{}}
	handleCreatePrinter(conn, req, m)

	var resp ipc.Response[any]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.Nil(t, resp.Result)
	assert.NotNil(t, resp.Error)
}

func TestHandleDeletePrinter(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().DeletePrinter("printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.deletePrinter",
		Params: map[string]any{"printerName": "printer1"},
	}
	handleDeletePrinter(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleAcceptJobs(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().AcceptJobs("printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.acceptJobs",
		Params: map[string]any{"printerName": "printer1"},
	}
	handleAcceptJobs(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleRejectJobs(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().RejectJobs("printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.rejectJobs",
		Params: map[string]any{"printerName": "printer1"},
	}
	handleRejectJobs(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleSetPrinterShared(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().SetPrinterIsShared("printer1", true).Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.setPrinterShared",
		Params: map[string]any{"printerName": "printer1", "shared": true},
	}
	handleSetPrinterShared(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleSetPrinterLocation(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().SetPrinterLocation("printer1", "Office").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.setPrinterLocation",
		Params: map[string]any{"printerName": "printer1", "location": "Office"},
	}
	handleSetPrinterLocation(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleSetPrinterInfo(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().SetPrinterInformation("printer1", "Main Printer").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.setPrinterInfo",
		Params: map[string]any{"printerName": "printer1", "info": "Main Printer"},
	}
	handleSetPrinterInfo(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleMoveJob(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().MoveJob(1, "printer2").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.moveJob",
		Params: map[string]any{"jobID": float64(1), "destPrinter": "printer2"},
	}
	handleMoveJob(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandlePrintTestPage(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().PrintTestPage("printer1", mock.Anything, mock.Anything).Return(42, nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.printTestPage",
		Params: map[string]any{"printerName": "printer1"},
	}
	handlePrintTestPage(conn, req, m)

	var resp ipc.Response[TestPageResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
	assert.Equal(t, 42, resp.Result.JobID)
}

func TestHandleAddPrinterToClass(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().AddPrinterToClass("office", "printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.addPrinterToClass",
		Params: map[string]any{"className": "office", "printerName": "printer1"},
	}
	handleAddPrinterToClass(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleRemovePrinterFromClass(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().DeletePrinterFromClass("office", "printer1").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.removePrinterFromClass",
		Params: map[string]any{"className": "office", "printerName": "printer1"},
	}
	handleRemovePrinterFromClass(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleDeleteClass(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().DeleteClass("office").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.deleteClass",
		Params: map[string]any{"className": "office"},
	}
	handleDeleteClass(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleRestartJob(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().RestartJob(1).Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.restartJob",
		Params: map[string]any{"jobID": float64(1)},
	}
	handleRestartJob(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleHoldJob(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().HoldJobUntil(1, "indefinite").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.holdJob",
		Params: map[string]any{"jobID": float64(1)},
	}
	handleHoldJob(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}

func TestHandleHoldJob_WithHoldUntil(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().HoldJobUntil(1, "no-hold").Return(nil)
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	m := NewTestManager(mockClient, nil)
	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{
		ID:     1,
		Method: "cups.holdJob",
		Params: map[string]any{"jobID": float64(1), "holdUntil": "no-hold"},
	}
	handleHoldJob(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	err := json.NewDecoder(buf).Decode(&resp)
	assert.NoError(t, err)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)
}
