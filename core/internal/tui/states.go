package tui

type ApplicationState int

const (
	StateWelcome ApplicationState = iota
	StateSelectWindowManager
	StateSelectTerminal
	StateDetectingDeps
	StateDependencyReview
	StateLayerPackages
	StateGentooUseFlags
	StateGentooGCCCheck
	StateSelectPrivesc
	StateAuthMethodChoice
	StateFingerprintAuth
	StatePasswordPrompt
	StateInstallingPackages
	StateConfigConfirmation
	StateDeployingConfigs
	StateInstallComplete
	StateError
)
