package cups

import (
	"io"
	"net"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/pkg/ipp"
)

type CUPSState struct {
	Printers map[string]*Printer `json:"printers"`
}

type Printer struct {
	Name        string `json:"name"`
	URI         string `json:"uri"`
	State       string `json:"state"`
	StateReason string `json:"stateReason"`
	Location    string `json:"location"`
	Info        string `json:"info"`
	MakeModel   string `json:"makeModel"`
	Accepting   bool   `json:"accepting"`
	Jobs        []Job  `json:"jobs"`
}

type Job struct {
	ID          int       `json:"id"`
	Name        string    `json:"name"`
	State       string    `json:"state"`
	Printer     string    `json:"printer"`
	User        string    `json:"user"`
	Size        int       `json:"size"`
	TimeCreated time.Time `json:"timeCreated"`
}

type Device struct {
	URI       string `json:"uri"`
	Class     string `json:"class"`
	Info      string `json:"info"`
	MakeModel string `json:"makeModel"`
	ID        string `json:"id"`
	Location  string `json:"location"`
	IP        string `json:"ip,omitempty"`
}

type PPD struct {
	Name            string `json:"name"`
	NaturalLanguage string `json:"naturalLanguage"`
	MakeModel       string `json:"makeModel"`
	DeviceID        string `json:"deviceId"`
	Product         string `json:"product"`
	PSVersion       string `json:"psVersion"`
	Type            string `json:"type"`
}

type RemotePrinterInfo struct {
	Reachable bool   `json:"reachable"`
	MakeModel string `json:"makeModel"`
	Name      string `json:"name"`
	Info      string `json:"info"`
	State     string `json:"state"`
	URI       string `json:"uri"`
	Error     string `json:"error,omitempty"`
}

type PrinterClass struct {
	Name     string   `json:"name"`
	URI      string   `json:"uri"`
	State    string   `json:"state"`
	Members  []string `json:"members"`
	Location string   `json:"location"`
	Info     string   `json:"info"`
}

type Manager struct {
	state             *CUPSState
	client            CUPSClientInterface
	pkHelper          PkHelper
	subscription      SubscriptionManagerInterface
	subLifecycleMu    sync.Mutex
	stateMutex        sync.RWMutex
	subscribers       syncmap.Map[string, chan CUPSState]
	stopChan          chan struct{}
	eventWG           sync.WaitGroup
	dirty             chan struct{}
	notifierWg        sync.WaitGroup
	lastNotifiedState *CUPSState
	baseURL           string
	probeRemoteFn     func(host string, port int, useTLS bool) (*RemotePrinterInfo, error)
	dialFn            func(network, addr string, timeout time.Duration) (net.Conn, error)
}

type SubscriptionManagerInterface interface {
	Start() error
	Stop()
	Events() <-chan SubscriptionEvent
}

type CUPSClientInterface interface {
	GetPrinters(attributes []string) (map[string]ipp.Attributes, error)
	GetJobs(printer, class string, whichJobs string, myJobs bool, firstJobId, limit int, attributes []string) (map[int]ipp.Attributes, error)
	CancelJob(jobID int, purge bool) error
	PausePrinter(printer string) error
	ResumePrinter(printer string) error
	CancelAllJob(printer string, purge bool) error
	SendRequest(url string, req *ipp.Request, additionalResponseData io.Writer) (*ipp.Response, error)

	GetDevices() (map[string]ipp.Attributes, error)
	GetPPDs() (map[string]ipp.Attributes, error)
	GetClasses(attributes []string) (map[string]ipp.Attributes, error)
	CreatePrinter(name, deviceURI, ppd string, shared bool, errorPolicy, information, location string) error
	DeletePrinter(printer string) error
	AcceptJobs(printer string) error
	RejectJobs(printer string) error
	SetPrinterIsShared(printer string, shared bool) error
	SetPrinterLocation(printer, location string) error
	SetPrinterInformation(printer, information string) error
	MoveJob(jobID int, destPrinter string) error
	PrintTestPage(printer string, testPageData io.Reader, size int) (int, error)
	AddPrinterToClass(class, printer string) error
	DeletePrinterFromClass(class, printer string) error
	DeleteClass(class string) error
	RestartJob(jobID int) error
	HoldJobUntil(jobID int, holdUntil string) error
}

type SubscriptionEvent struct {
	EventName    string
	PrinterName  string
	JobID        int
	SubscribedAt time.Time
}
