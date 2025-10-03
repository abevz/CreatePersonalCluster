// File: internal/tofu/executor.go
package tofu

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
)

// runCommand is a helper to execute external commands with real-time output and environment variables.
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

// Plan runs 'init', sets permissions, selects workspace, and runs 'plan'.
func Plan(workDir string, cfg *config.Deployment) error {
	env := map[string]string{
		"AWS_ACCESS_KEY_ID":     cfg.S3BackendCredentials.AccessKey,
		"AWS_SECRET_ACCESS_KEY": cfg.S3BackendCredentials.SecretKey,
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
		// This is not a fatal error, so we just log a warning
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

// Apply runs 'init', sets permissions, selects workspace, and runs 'apply'.
func Apply(workDir string, cfg *config.Deployment) (map[string]interface{}, error) {
	env := map[string]string{
		"AWS_ACCESS_KEY_ID":     cfg.S3BackendCredentials.AccessKey,
		"AWS_SECRET_ACCESS_KEY": cfg.S3BackendCredentials.SecretKey,
	}
	workspaceName := cfg.Metadata.Name

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

	// Step 5: Fetch outputs
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
