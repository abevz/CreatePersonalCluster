// File: internal/tofu/snippets.go
package tofu

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
)

// SnippetData holds the values to be injected into the cloud-init template.
type SnippetData struct {
	Hostname string
	Username string
}

// GenerateSnippets creates cloud-init user-data files for all nodes IF a template is specified.
func GenerateSnippets(cfg *config.Deployment, deploymentPath, workDir string) error {
	// --- NEW: Check if a template is specified at all ---
	if cfg.Spec.CloudInitTemplate == "" {
		log.Println("   'cloudInitTemplate' not specified in deployment.yaml, skipping snippet generation.")
		return nil
	}

	snippetsDir := filepath.Join(workDir, "snippets")
	if err := os.MkdirAll(snippetsDir, 0o755); err != nil {
		return fmt.Errorf("failed to create snippets directory: %w", err)
	}

	// --- NEW: Template path is now dynamic ---
	// It's relative to the deployment directory (where deployment.yaml is)
	templatePath := filepath.Join(deploymentPath, cfg.Spec.CloudInitTemplate)
	log.Printf("   Using cloud-init template: %s", templatePath)

	tmpl, err := template.ParseFiles(templatePath)
	if err != nil {
		return fmt.Errorf("failed to parse cloud-init template file %s: %w", templatePath, err)
	}

	nodeCount := 0
	for _, group := range cfg.Spec.NodeGroups {
		for i := 1; i <= group.Count; i++ {
			nodeCount++
			hostname := fmt.Sprintf("%s%d.%s", group.RolePrefix, i, cfg.Spec.ClusterDomain)

			// Legacy file naming for compatibility with old HCL
			releaseLetter := cfg.Spec.Variables["release_letter"].(string)
			legacyRole := strings.TrimSuffix(group.RolePrefix, releaseLetter)
			fileName := fmt.Sprintf("node-%s%s%d-userdata.yaml", legacyRole, releaseLetter, i)
			filePath := filepath.Join(snippetsDir, fileName)

			data := SnippetData{
				Hostname: hostname,
				Username: cfg.PostInstallSecrets.VMCredentials.Username,
			}

			file, err := os.Create(filePath)
			if err != nil {
				return fmt.Errorf("failed to create snippet file %s: %w", fileName, err)
			}
			defer file.Close()

			if err := tmpl.Execute(file, data); err != nil {
				return fmt.Errorf("failed to execute template for %s: %w", fileName, err)
			}
		}
	}

	log.Printf("Successfully generated %d snippet files in %s", nodeCount, snippetsDir)
	return nil
}
