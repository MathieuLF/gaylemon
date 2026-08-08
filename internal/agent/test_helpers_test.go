package agent

import "os"

func osWriteFile(path string, content []byte) error {
	return os.WriteFile(path, content, 0o600)
}
