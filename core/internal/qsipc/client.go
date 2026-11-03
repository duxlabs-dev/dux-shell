package qsipc

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"path/filepath"
	"time"
	"unicode/utf16"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	commandStringCall = 3

	// Keep these indexes in sync with quickshell-mirror/quickshell:
	// https://github.com/quickshell-mirror/quickshell/blob/59e9c47/src/io/ipccomm.cpp#L126
	responseNotReady         = 1
	responseTargetNotFound   = 2
	responseFunctionNotFound = 3
	responseArgumentMismatch = 4
	responseCompleted        = 5
	maxStringLength          = 1 << 20
)

var (
	ErrNotReady            = errors.New("quickshell IPC not ready")
	ErrTargetNotFound      = errors.New("quickshell IPC target not found")
	ErrFunctionNotFound    = errors.New("quickshell IPC function not found")
	ErrArgumentMismatch    = errors.New("quickshell IPC argument mismatch")
	ErrUnsupportedResponse = errors.New("unsupported Quickshell IPC response")
)

// Call invokes a Quickshell IpcHandler without starting a qs child process.
func Call(socketPath, target, function string, args []string) (string, bool, error) {
	conn, err := net.DialTimeout("unix", socketPath, 2*time.Second)
	if err != nil {
		return "", false, fmt.Errorf("connect to Quickshell IPC: %w", err)
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(2 * time.Second))
	if err := writeCall(conn, target, function, args); err != nil {
		return "", false, fmt.Errorf("write Quickshell IPC request: %w", err)
	}

	result, isVoid, err := readResponse(bufio.NewReader(conn))
	if err != nil {
		return "", false, err
	}
	return result, isVoid, nil
}

func writeCall(w io.Writer, target, function string, args []string) error {
	var buf bytes.Buffer
	if err := buf.WriteByte(commandStringCall); err != nil {
		return err
	}
	if err := writeQString(&buf, target); err != nil {
		return err
	}
	if err := writeQString(&buf, function); err != nil {
		return err
	}
	if err := binary.Write(&buf, binary.BigEndian, uint32(len(args))); err != nil {
		return err
	}
	for _, arg := range args {
		if err := writeQString(&buf, arg); err != nil {
			return err
		}
	}
	_, err := w.Write(buf.Bytes())
	return err
}

func readResponse(r io.Reader) (string, bool, error) {
	var index uint8
	if err := binary.Read(r, binary.BigEndian, &index); err != nil {
		return "", false, fmt.Errorf("read Quickshell IPC response: %w", err)
	}
	switch index {
	case responseNotReady:
		return "", false, ErrNotReady
	case responseTargetNotFound:
		return "", false, ErrTargetNotFound
	case responseFunctionNotFound:
		return "", false, ErrFunctionNotFound
	case responseArgumentMismatch:
		return "", false, ErrArgumentMismatch
	case responseCompleted:
		break
	default:
		return "", false, fmt.Errorf("%w: variant index %d", ErrUnsupportedResponse, index)
	}

	var isVoid uint8
	if err := binary.Read(r, binary.BigEndian, &isVoid); err != nil {
		return "", false, fmt.Errorf("read Quickshell IPC completion: %w", err)
	}
	value, err := readQString(r)
	if err != nil {
		return "", false, fmt.Errorf("read Quickshell IPC result: %w", err)
	}
	return value, isVoid != 0, nil
}

func writeQString(w io.Writer, value string) error {
	encoded := utf16.Encode([]rune(value))
	byteLength := len(encoded) * 2
	if byteLength > maxStringLength {
		return fmt.Errorf("QString is too large: %d bytes", byteLength)
	}
	if err := binary.Write(w, binary.BigEndian, uint32(byteLength)); err != nil {
		return err
	}
	for _, codeUnit := range encoded {
		if err := binary.Write(w, binary.BigEndian, codeUnit); err != nil {
			return err
		}
	}
	return nil
}

func readQString(r io.Reader) (string, error) {
	var length uint32
	if err := binary.Read(r, binary.BigEndian, &length); err != nil {
		return "", err
	}
	if length == ^uint32(0) {
		return "", nil
	}
	if length > maxStringLength || length%2 != 0 {
		return "", fmt.Errorf("invalid QString length: %d bytes", length)
	}
	codeUnits := make([]uint16, length/2)
	for i := range codeUnits {
		if err := binary.Read(r, binary.BigEndian, &codeUnits[i]); err != nil {
			return "", err
		}
	}
	return string(utf16.Decode(codeUnits)), nil
}

// SocketPathForPID returns the instance IPC socket used by qs --pid.
func SocketPathForPID(pid int) string {
	return filepath.Join(utils.RuntimeDir(), "quickshell", "by-pid", fmt.Sprint(pid), "ipc.sock")
}
