package cups_test

import (
	"testing"

	mocks_cups "github.com/duxlabs-dev/dux-shell/core/internal/mocks/cups"
	mocks_pkhelper "github.com/duxlabs-dev/dux-shell/core/internal/mocks/cups_pkhelper"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/cups"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func authErr() error {
	return ipp.IPPError{Status: ipp.StatusErrorForbidden}
}

func TestManager_CancelJob_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().CancelJob(1, false).Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().JobCancelPurge(1, false).Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.CancelJob(1))
}

func TestManager_CancelJob_PkHelperError(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().CancelJob(1, false).Return(authErr())

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().JobCancelPurge(1, false).Return(assert.AnError)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.Error(t, m.CancelJob(1))
}

func TestManager_PausePrinter_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().PausePrinter("printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetEnabled("printer1", false).Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.PausePrinter("printer1"))
}

func TestManager_ResumePrinter_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().ResumePrinter("printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetEnabled("printer1", true).Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.ResumePrinter("printer1"))
}

func TestManager_GetDevices_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().DevicesGet(10, 0, []string(nil), []string(nil)).Return([]cups.Device{
		{URI: "usb://HP/LaserJet", Class: "direct"},
	}, nil)

	m := cups.NewTestManager(mockClient, mockPk)
	got, err := m.GetDevices()
	assert.NoError(t, err)
	assert.Len(t, got, 1)
	assert.Equal(t, "usb://HP/LaserJet", got[0].URI)
}

func TestManager_GetDevices_PkHelperError(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().DevicesGet(10, 0, []string(nil), []string(nil)).Return(nil, assert.AnError)

	m := cups.NewTestManager(mockClient, mockPk)
	_, err := m.GetDevices()
	assert.Error(t, err)
}

func TestManager_CreatePrinter_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().CreatePrinter("newprinter", "usb://HP", "generic.ppd", true, "stop-printer", "info", "location").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterAdd("newprinter", "usb://HP", "generic.ppd", "info", "location").Return(nil)
	mockPk.EXPECT().PrinterSetEnabled("newprinter", true).Return(nil)
	mockPk.EXPECT().PrinterSetAcceptJobs("newprinter", true, "").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.CreatePrinter("newprinter", "usb://HP", "generic.ppd", true, "stop-printer", "info", "location"))
}

func TestManager_DeletePrinter_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().DeletePrinter("printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterDelete("printer1").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.DeletePrinter("printer1"))
}

func TestManager_AcceptJobs_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().AcceptJobs("printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetAcceptJobs("printer1", true, "").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.AcceptJobs("printer1"))
}

func TestManager_RejectJobs_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().RejectJobs("printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetAcceptJobs("printer1", false, "").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.RejectJobs("printer1"))
}

func TestManager_SetPrinterShared_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().SetPrinterIsShared("printer1", true).Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetShared("printer1", true).Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.SetPrinterShared("printer1", true))
}

func TestManager_SetPrinterLocation_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().SetPrinterLocation("printer1", "Office").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetLocation("printer1", "Office").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.SetPrinterLocation("printer1", "Office"))
}

func TestManager_SetPrinterInfo_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().SetPrinterInformation("printer1", "Main Printer").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().PrinterSetInfo("printer1", "Main Printer").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.SetPrinterInfo("printer1", "Main Printer"))
}

func TestManager_AddPrinterToClass_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().AddPrinterToClass("office", "printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().ClassAddPrinter("office", "printer1").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.AddPrinterToClass("office", "printer1"))
}

func TestManager_RemovePrinterFromClass_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().DeletePrinterFromClass("office", "printer1").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().ClassDeletePrinter("office", "printer1").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.RemovePrinterFromClass("office", "printer1"))
}

func TestManager_DeleteClass_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().DeleteClass("office").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().ClassDelete("office").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.DeleteClass("office"))
}

func TestManager_RestartJob_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().RestartJob(1).Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().JobRestart(1).Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.RestartJob(1))
}

func TestManager_HoldJob_WithPkHelper(t *testing.T) {
	mockClient := mocks_cups.NewMockCUPSClientInterface(t)
	mockClient.EXPECT().HoldJobUntil(1, "indefinite").Return(authErr())
	mockClient.EXPECT().GetPrinters(mock.Anything).Return(map[string]ipp.Attributes{}, nil)

	mockPk := mocks_pkhelper.NewMockPkHelper(t)
	mockPk.EXPECT().JobSetHoldUntil(1, "indefinite").Return(nil)

	m := cups.NewTestManager(mockClient, mockPk)
	assert.NoError(t, m.HoldJob(1, "indefinite"))
}
