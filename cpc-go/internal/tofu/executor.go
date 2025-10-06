// File: internal/tofu/executor.go
package tofu

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath" // <--- НОВЫЙ ИМПОРТ

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
)

// НОВАЯ ФУНКЦИЯ для подготовки окружения Tofu
// Она берет базовые переменные и добавляет к ним путь к кэшу плагинов.
func getTofuEnv(baseEnv map[string]string) (map[string]string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get user home directory: %w", err)
	}

	pluginCacheDir := filepath.Join(homeDir, ".cpc", "plugin-cache")
	if err := os.MkdirAll(pluginCacheDir, 0o755); err != nil {
		// Если не удалось создать папку, просто выводим предупреждение, но не останавливаем выполнение
		log.Printf("Warning: could not create plugin cache directory at %s: %v", pluginCacheDir, err)
	} else {
		// Если папка есть, добавляем переменную
		baseEnv["TF_PLUGIN_CACHE_DIR"] = pluginCacheDir
	}

	return baseEnv, nil
}

// runCommand остается без изменений
func runCommand(workDir string, envVars map[string]string, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	for key, val := range envVars {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", key, val))
	}
	log.Printf("   Executing in '%s': %s %v\n", workDir, name, args)
	return cmd.Run()
}

// Plan теперь использует getTofuEnv
func Plan(workDir string, cfg *config.Deployment) error {
	baseEnv := map[string]string{
		"AWS_ACCESS_KEY_ID":     cfg.S3BackendCredentials.AccessKey,
		"AWS_SECRET_ACCESS_KEY": cfg.S3BackendCredentials.SecretKey,
	}
	// Получаем полное окружение с кэшем
	env, err := getTofuEnv(baseEnv)
	if err != nil {
		return err // Если не можем получить home dir, это фатальная ошибка
	}

	workspaceName := cfg.Metadata.Name

	// Step 1: Initialize
	log.Println("   Initializing OpenTofu backend...")
	if err := runCommand(workDir, env, "tofu", "init", "-input=false", "-no-color", "-reconfigure"); err != nil {
		return fmt.Errorf("'tofu init' failed: %w", err)
	}

	// NEW STEP 2: Make provider binaries executable
	log.Println("   Setting provider permissions...")
	chmodCmd := `find .terraform/providers -type f -name 'terraform-provider-*' -exec chmod +x {} +`
	if err := runCommand(workDir, env, "bash", "-c", chmodCmd); err != nil {
		log.Printf("Warning: failed to chmod providers, plan may fail: %v", err)
	}

	// Step 3: Select workspace
	log.Println("   Selecting OpenTofu workspace...")
	workspaceCommand := fmt.Sprintf("tofu workspace select %s || tofu workspace new %s", workspaceName, workspaceName)
	if err := runCommand(workDir, env, "bash", "-c", workspaceCommand); err != nil {
		return fmt.Errorf("'tofu workspace select' failed: %w", err)
	}

	// Step 4: Plan
	log.Println("   Creating execution plan...")
	if err := runCommand(workDir, env, "tofu", "plan", "-var-file=terraform.tfvars.json", "-no-color"); err != nil {
		return fmt.Errorf("'tofu plan' failed: %w", err)
	}
	return nil
}

// Apply теперь использует getTofuEnv
func Apply(workDir string, cfg *config.Deployment) (map[string]interface{}, error) {
	baseEnv := map[string]string{
		"AWS_ACCESS_KEY_ID":     cfg.S3BackendCredentials.AccessKey,
		"AWS_SECRET_ACCESS_KEY": cfg.S3BackendCredentials.SecretKey,
	}
	// Получаем полное окружение с кэшем
	env, err := getTofuEnv(baseEnv)
	if err != nil {
		return nil, err
	}

	workspaceName := cfg.Metadata.Name

	// ... (все остальные шаги в Apply остаются такими же, но используют новую переменную 'env')
	// Step 1: Initialize
	log.Println("   Initializing OpenTofu backend...")
	if err := runCommand(workDir, env, "tofu", "init", "-input=false", "-no-color", "-reconfigure"); err != nil {
		return nil, fmt.Errorf("'tofu init' failed: %w", err)
	}

	// NEW STEP 2: Make provider binaries executable
	log.Println("   Setting provider permissions...")
	chmodCmd := `find .terraform/providers -type f -name 'terraform-provider-*' -exec chmod +x {} +`
	if err := runCommand(workDir, env, "bash", "-c", chmodCmd); err != nil {
		log.Printf("Warning: failed to chmod providers, apply may fail: %v", err)
	}

	// Step 3: Select workspace
	log.Println("   Selecting OpenTofu workspace...")
	workspaceCommand := fmt.Sprintf("tofu workspace select %s || tofu workspace new %s", workspaceName, workspaceName)
	if err := runCommand(workDir, env, "bash", "-c", workspaceCommand); err != nil {
		return nil, fmt.Errorf("'tofu workspace select' failed: %w", err)
	}

	// Step 4: Apply
	log.Println("   Applying changes...")
	applyArgs := []string{"apply", "-auto-approve", "-var-file=terraform.tfvars.json", "-no-color"}
	if err := runCommand(workDir, env, "tofu", applyArgs...); err != nil {
		return nil, fmt.Errorf("'tofu apply' failed: %w", err)
	}

	// ... (код для 'tofu output' остается без изменений) ...
	log.Println("   Fetching outputs...")
	cmd := exec.Command("tofu", "output", "-json")
	cmd.Dir = workDir
	var out bytes.Buffer
	cmd.Stdout = &out
	var errBuf bytes.Buffer
	cmd.Stderr = &errBuf
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("'tofu output' failed: %s: %w", errBuf.String(), err)
	}
	var outputs map[string]interface{}
	if err := json.Unmarshal(out.Bytes(), &outputs); err != nil {
		return nil, fmt.Errorf("failed to parse JSON from 'tofu output': %w", err)
	}
	return outputs, nil
}
