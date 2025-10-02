// File: internal/tofu/executor.go
// package tofu (продолжение)
package tofu

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
)

// runCommand - хелпер для запуска внешних команд и вывода их логов в реальном времени.
func runCommand(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	fmt.Printf("   -> Executing: %s %v\n", name, args)
	return cmd.Run()
}

// Execute запускает `tofu init` и `tofu apply`.
func Execute(dir string) (map[string]interface{}, error) {
	if err := runCommand(dir, "tofu", "init"); err != nil {
		return nil, fmt.Errorf("'tofu init' failed: %w", err)
	}

	if err := runCommand(dir, "tofu", "apply", "-auto-approve", "-var-file=terraform.tfvars.json"); err != nil {
		return nil, fmt.Errorf("'tofu apply' failed: %w", err)
	}

	// Получаем output
	cmd := exec.Command("tofu", "output", "-json")
	cmd.Dir = dir
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("'tofu output' failed: %w", err)
	}

	var outputs map[string]interface{}
	if err := json.Unmarshal(out.Bytes(), &outputs); err != nil {
		return nil, fmt.Errorf("failed to parse tofu output json: %w", err)
	}

	return outputs, nil
}
