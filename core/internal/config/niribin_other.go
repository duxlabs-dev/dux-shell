//go:build !linux

package config

func runningNiriExe() string {
	return ""
}
