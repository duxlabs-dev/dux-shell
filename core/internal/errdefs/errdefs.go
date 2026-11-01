package errdefs

import (
	dankerrdefs "github.com/duxlabs-dev/dux-go/errdefs"
)

type ErrorType = dankerrdefs.ErrorType

type CustomError = dankerrdefs.CustomError

const (
	ErrTypeNotLinux ErrorType = dankerrdefs.AppErrorBase + iota
	ErrTypeInvalidArchitecture
	ErrTypeUnsupportedDistribution
	ErrTypeUnsupportedVersion
	ErrTypeUpdateCancelled
	ErrTypeNoUpdateNeeded
	ErrTypeInvalidTemperature
	ErrTypeInvalidGamma
	ErrTypeInvalidLocation
	ErrTypeInvalidManualTimes
	ErrTypeNoWaylandDisplay
	ErrTypeNoGammaControl
	ErrTypeNotInitialized
	ErrTypeSecretPromptCancelled
	ErrTypeSecretPromptTimeout
	ErrTypeSecretAgentFailed
	ErrTypeGeneric
	ErrTypeInvalidDuration
	ErrTypeInvalidContrast
)

func NewCustomError(errType ErrorType, message string) error {
	return dankerrdefs.NewCustomError(errType, message)
}

const (
	ErrBadCredentials   = "bad-credentials"
	ErrNoSuchSSID       = "no-such-ssid"
	ErrAssocTimeout     = "assoc-timeout"
	ErrDhcpTimeout      = "dhcp-timeout"
	ErrUserCanceled     = "user-canceled"
	ErrWifiDisabled     = "wifi-disabled"
	ErrAlreadyConnected = "already-connected"
	ErrConnectionFailed = "connection-failed"

	ErrHotspotIPConfigFailed   = "hotspot-ip-config-failed"
	ErrHotspotSupplicantFailed = "hotspot-supplicant-failed"
	ErrHotspotFailed           = "hotspot-failed"
)

var (
	ErrUpdateCancelled       = NewCustomError(ErrTypeUpdateCancelled, "update cancelled by user")
	ErrNoUpdateNeeded        = NewCustomError(ErrTypeNoUpdateNeeded, "no update needed")
	ErrInvalidTemperature    = NewCustomError(ErrTypeInvalidTemperature, "temperature must be between 1000 and 10000")
	ErrInvalidGamma          = NewCustomError(ErrTypeInvalidGamma, "gamma must be between 0 and 10")
	ErrInvalidContrast       = NewCustomError(ErrTypeInvalidContrast, "contrast must be between 0.5 and 2")
	ErrInvalidLocation       = NewCustomError(ErrTypeInvalidLocation, "invalid latitude/longitude")
	ErrInvalidManualTimes    = NewCustomError(ErrTypeInvalidManualTimes, "both sunrise and sunset must be set or neither")
	ErrInvalidDuration       = NewCustomError(ErrTypeInvalidDuration, "duration must be between 0 and 6 hours")
	ErrNoWaylandDisplay      = NewCustomError(ErrTypeNoWaylandDisplay, "no wayland display available")
	ErrNoGammaControl        = NewCustomError(ErrTypeNoGammaControl, "compositor does not support gamma control")
	ErrNotInitialized        = NewCustomError(ErrTypeNotInitialized, "manager not initialized")
	ErrSecretPromptCancelled = NewCustomError(ErrTypeSecretPromptCancelled, "secret prompt cancelled by user")
	ErrSecretPromptTimeout   = NewCustomError(ErrTypeSecretPromptTimeout, "secret prompt timed out")
	ErrSecretAgentFailed     = NewCustomError(ErrTypeSecretAgentFailed, "secret agent operation failed")
)
