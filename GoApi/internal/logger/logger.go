// Package logger provides structured logging utilities.
package logger

import (
	"fmt"
	"log"
	"os"
)

// Logger defines the logging interface.
type Logger interface {
	Info(msg string, keysAndValues ...interface{})
	Error(msg string, keysAndValues ...interface{})
	Debug(msg string, keysAndValues ...interface{})
	Warn(msg string, keysAndValues ...interface{})
}

// StandardLogger implements Logger using Go's standard log package.
type StandardLogger struct {
	infoLogger  *log.Logger
	errorLogger *log.Logger
	debugLogger *log.Logger
	warnLogger  *log.Logger
}

// New creates a new StandardLogger instance.
func New() Logger {
	return &StandardLogger{
		infoLogger:  log.New(os.Stdout, "[INFO] ", log.Ldate|log.Ltime|log.Lshortfile),
		errorLogger: log.New(os.Stderr, "[ERROR] ", log.Ldate|log.Ltime|log.Lshortfile),
		debugLogger: log.New(os.Stdout, "[DEBUG] ", log.Ldate|log.Ltime|log.Lshortfile),
		warnLogger:  log.New(os.Stdout, "[WARN] ", log.Ldate|log.Ltime|log.Lshortfile),
	}
}

// Info logs an info message with optional key-value pairs.
func (l *StandardLogger) Info(msg string, keysAndValues ...interface{}) {
	l.infoLogger.Println(formatMessage(msg, keysAndValues...))
}

// Error logs an error message with optional key-value pairs.
func (l *StandardLogger) Error(msg string, keysAndValues ...interface{}) {
	l.errorLogger.Println(formatMessage(msg, keysAndValues...))
}

// Debug logs a debug message with optional key-value pairs.
func (l *StandardLogger) Debug(msg string, keysAndValues ...interface{}) {
	l.debugLogger.Println(formatMessage(msg, keysAndValues...))
}

// Warn logs a warning message with optional key-value pairs.
func (l *StandardLogger) Warn(msg string, keysAndValues ...interface{}) {
	l.warnLogger.Println(formatMessage(msg, keysAndValues...))
}

// formatMessage formats the message with key-value pairs.
func formatMessage(msg string, keysAndValues ...interface{}) string {
	if len(keysAndValues) == 0 {
		return msg
	}

	formatted := msg
	for i := 0; i < len(keysAndValues); i += 2 {
		if i+1 < len(keysAndValues) {
			formatted += " " + keysAndValues[i].(string) + "=" + formatValue(keysAndValues[i+1])
		}
	}
	return formatted
}

// formatValue converts a value to a string representation.
func formatValue(v interface{}) string {
	if v == nil {
		return "nil"
	}
	if err, ok := v.(error); ok {
		return err.Error()
	}
	return fmt.Sprint(v)
}
