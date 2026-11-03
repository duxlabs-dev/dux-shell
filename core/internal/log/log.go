package log

import (
	danklog "github.com/duxlabs-dev/dux-go/log"
)

type Logger = danklog.Logger

func init() {
	danklog.SetEnvPrefix("DMS")
}

func GetLogger() *Logger { return danklog.GetLogger() }

func GetQtLoggingRules() string { return danklog.GetQtLoggingRules() }

func SetLevel(level string) { danklog.SetLevel(level) }

func SetLogFile(path string) error { return danklog.SetLogFile(path) }

func ApplyEnvOverrides() { danklog.ApplyEnvOverrides() }

func Debug(msg any, keyvals ...any)  { danklog.Debug(msg, keyvals...) }
func Debugf(format string, v ...any) { danklog.Debugf(format, v...) }
func Info(msg any, keyvals ...any)   { danklog.Info(msg, keyvals...) }
func Infof(format string, v ...any)  { danklog.Infof(format, v...) }
func Warn(msg any, keyvals ...any)   { danklog.Warn(msg, keyvals...) }
func Warnf(format string, v ...any)  { danklog.Warnf(format, v...) }
func Error(msg any, keyvals ...any)  { danklog.Error(msg, keyvals...) }
func Errorf(format string, v ...any) { danklog.Errorf(format, v...) }
func Fatal(msg any, keyvals ...any)  { danklog.Fatal(msg, keyvals...) }
func Fatalf(format string, v ...any) { danklog.Fatalf(format, v...) }
