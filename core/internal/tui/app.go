package tui

import (
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

type Model struct {
	version string
	state   ApplicationState

	osInfo       *distros.OSInfo
	resume       *layerResume
	dependencies []deps.Dependency
	err          error

	spinner       spinner.Model
	passwordInput textinput.Model
	width         int
	height        int
	isLoading     bool
	styles        Styles

	logMessages         []string
	logChan             chan string
	logFilePath         string
	packageProgressChan chan packageInstallProgressMsg
	packageProgress     packageInstallProgressMsg
	installationLogs    []string
	showDebugLogs       bool

	selectedWM         int
	selectedTerminal   int
	selectedDep        int
	selectedConfig     int
	selectedAuthMethod int
	reinstallItems     map[string]bool
	detectedVariants   map[string]deps.PackageVariant
	variantMarks       map[string]bool
	disabledItems      map[string]bool
	replaceConfigs     map[string]bool
	skipGentooUseFlags bool
	sudoPassword       string
	existingConfigs    []ExistingConfigInfo
	fingerprintFailed  bool
	authValidating     bool
	authFailed         bool

	availablePrivesc []privesc.Tool
	selectedPrivesc  int
}

func NewModel(version string, logFilePath string) Model {
	styles := NewStyles(TerminalTheme())

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = styles.SpinnerStyle

	pi := textinput.New()
	pi.Placeholder = "Enter sudo password"
	pi.EchoMode = textinput.EchoPassword
	pi.EchoCharacter = '•'
	pi.Focus()

	return Model{
		version:             version,
		state:               StateWelcome,
		spinner:             s,
		passwordInput:       pi,
		isLoading:           true,
		styles:              styles,
		logChan:             make(chan string, 1000),
		logFilePath:         logFilePath,
		packageProgressChan: make(chan packageInstallProgressMsg, 100),
		packageProgress: packageInstallProgressMsg{
			step: "Initializing package installation",
		},
		reinstallItems:   make(map[string]bool),
		detectedVariants: make(map[string]deps.PackageVariant),
		variantMarks:     make(map[string]bool),
		disabledItems:    make(map[string]bool),
		replaceConfigs:   make(map[string]bool),
	}
}

func (m Model) GetLogChan() <-chan string {
	return m.logChan
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		m.listenForLogs(),
		m.detectOS(),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "ctrl+d":
			if m.state != StatePasswordPrompt && m.state != StateFingerprintAuth {
				m.showDebugLogs = !m.showDebugLogs
				return m, nil
			}
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, tea.Batch(cmd, m.listenForLogs())

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case logMsg:
		m.logMessages = append(m.logMessages, msg.message)
		return m, m.listenForLogs()
	}

	switch m.state {
	case StateWelcome:
		return m.updateWelcomeState(msg)
	case StateSelectWindowManager:
		return m.updateSelectWindowManagerState(msg)
	case StateSelectTerminal:
		return m.updateSelectTerminalState(msg)
	case StateDetectingDeps:
		return m.updateDetectingDepsState(msg)
	case StateDependencyReview:
		return m.updateDependencyReviewState(msg)
	case StateLayerPackages:
		return m.updateLayerPackagesState(msg)
	case StateGentooUseFlags:
		return m.updateGentooUseFlagsState(msg)
	case StateGentooGCCCheck:
		return m.updateGentooGCCCheckState(msg)
	case StateSelectPrivesc:
		return m.updateSelectPrivescState(msg)
	case StateAuthMethodChoice:
		return m.updateAuthMethodChoiceState(msg)
	case StateFingerprintAuth:
		return m.updateFingerprintAuthState(msg)
	case StatePasswordPrompt:
		return m.updatePasswordPromptState(msg)
	case StateInstallingPackages:
		return m.updateInstallingPackagesState(msg)
	case StateConfigConfirmation:
		return m.updateConfigConfirmationState(msg)
	case StateDeployingConfigs:
		return m.updateDeployingConfigsState(msg)
	case StateInstallComplete:
		return m.updateInstallCompleteState(msg)
	case StateError:
		return m.updateErrorState(msg)
	default:
		return m, m.listenForLogs()
	}
}

func (m Model) View() string {
	if m.showDebugLogs {
		return m.viewDebugLogs()
	}

	switch m.state {
	case StateWelcome:
		return m.viewWelcome()
	case StateSelectWindowManager:
		return m.viewSelectWindowManager()
	case StateSelectTerminal:
		return m.viewSelectTerminal()
	case StateDetectingDeps:
		return m.viewDetectingDeps()
	case StateDependencyReview:
		return m.viewDependencyReview()
	case StateLayerPackages:
		return m.viewLayerPackages()
	case StateGentooUseFlags:
		return m.viewGentooUseFlags()
	case StateGentooGCCCheck:
		return m.viewGentooGCCCheck()
	case StateSelectPrivesc:
		return m.viewSelectPrivesc()
	case StateAuthMethodChoice:
		return m.viewAuthMethodChoice()
	case StateFingerprintAuth:
		return m.viewFingerprintAuth()
	case StatePasswordPrompt:
		return m.viewPasswordPrompt()
	case StateInstallingPackages:
		return m.viewInstallingPackages()
	case StateConfigConfirmation:
		return m.viewConfigConfirmation()
	case StateDeployingConfigs:
		return m.viewDeployingConfigs()
	case StateInstallComplete:
		return m.viewInstallComplete()
	case StateError:
		return m.viewError()
	default:
		return m.viewWelcome()
	}
}

func (m Model) startInstallation(password string) (tea.Model, tea.Cmd) {
	m.sudoPassword = password
	m.passwordInput.SetValue("")
	m.authValidating = false
	m.authFailed = false
	m.packageProgress = packageInstallProgressMsg{}
	m.state = StateInstallingPackages
	m.isLoading = true
	return m, tea.Batch(m.spinner.Tick, m.installPackages())
}

func (m Model) promptForPassword() (tea.Model, tea.Cmd) {
	m.authValidating = false
	m.authFailed = false
	m.passwordInput.SetValue("")
	m.passwordInput.Focus()
	m.state = StatePasswordPrompt
	return m, nil
}

func (m Model) listenForLogs() tea.Cmd {
	return func() tea.Msg {
		select {
		case msg, ok := <-m.logChan:
			if !ok {
				return nil
			}
			return logMsg{message: msg}
		default:
			return nil
		}
	}
}

func (m Model) detectOS() tea.Cmd {
	return func() tea.Msg {
		info, err := distros.GetOSInfo()
		if info == nil {
			info = &distros.OSInfo{}
		}
		return osInfoCompleteMsg{info: info, err: err}
	}
}

func moveIndex(current, delta, max int) int {
	next := current + delta
	if next < 0 || next > max {
		return current
	}
	return next
}
