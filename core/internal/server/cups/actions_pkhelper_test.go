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
