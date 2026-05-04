package client

import (
	"fmt"
	"time"
)

// Logger is the gomobile-compatible logging interface.
// Implement this in Kotlin/Swift and pass to Client.SetLogger.
type Logger interface {
	Log(level string, category string, message string)
}

// noopLogger discards all log output. Used as default.
type noopLogger struct{}

func (noopLogger) Log(_, _, _ string) {}

// internalLogger is used inside the Go module to route log calls.
type internalLogger struct {
	delegate Logger
}

func newInternalLogger(delegate Logger) *internalLogger {
	if delegate == nil {
		return &internalLogger{delegate: noopLogger{}}
	}
	return &internalLogger{delegate: delegate}
}

func (l *internalLogger) debug(category, msg string, args ...interface{}) {
	l.delegate.Log("debug", category, fmt.Sprintf(msg, args...))
}

func (l *internalLogger) info(category, msg string, args ...interface{}) {
	l.delegate.Log("info", category, fmt.Sprintf(msg, args...))
}

func (l *internalLogger) warning(category, msg string, args ...interface{}) {
	l.delegate.Log("warning", category, fmt.Sprintf(msg, args...))
}

func (l *internalLogger) error(category, msg string, args ...interface{}) {
	l.delegate.Log("error", category, fmt.Sprintf(msg, args...))
}

// timestampedMessage returns a log message with UTC timestamp prefix.
func timestampedMessage(msg string) string {
	return fmt.Sprintf("[%s] %s", time.Now().UTC().Format("15:04:05.000"), msg)
}
