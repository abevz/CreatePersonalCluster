// File: internal/tofu/generator.go
package tofu

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"text/template"

	"github.com/knadh/koanf/v2"
)

// HCL-шаблоны. В реальном проекте их лучше вынести в отдельные .tpl файлы.
const mainTfTemplate = `
# Файл сгенерирован cpc-go
# ... здесь будет логика Proxmox, использующая переменные ...
# Например:
resource "proxmox_vm_qemu" "cluster_node" {
  count = var.node_count
  name  = "${var.cluster_name}-node-${count.index}"
  # ... другие параметры
}
`

const backendTfTemplate = `
# Файл сгенерирован cpc-go
terraform {
  backend "s3" {
    endpoint                    = "{{ .backend.s3.endpoint }}"
    bucket                      = "{{ .backend.s3.bucket }}"
    key                         = "{{ .backend.s3.key }}"
    region                      = "{{ .backend.s3.region }}"
    access_key                  = "{{ .backend.s3.access_key }}"
    secret_key                  = "{{ .backend.s3.secret_key }}"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}
`

// GenerateHCL создает все необходимые .tf файлы во временной директории.
func GenerateHCL(k *koanf.Koanf, dir string) error {
	// Создаем main.tf
	if err := os.WriteFile(filepath.Join(dir, "main.tf"), []byte(mainTfTemplate), 0o644); err != nil {
		return err
	}

	// Создаем backend.tf из шаблона
	backendTmpl, err := template.New("backend").Parse(backendTfTemplate)
	if err != nil {
		return fmt.Errorf("failed to parse backend template: %w", err)
	}

	backendFile, err := os.Create(filepath.Join(dir, "backend.tf"))
	if err != nil {
		return err
	}
	defer backendFile.Close()

	// Извлекаем данные для backend из конфига
	backendData := k.Get("spec.state.backend")
	if err := backendTmpl.Execute(backendFile, backendData); err != nil {
		return fmt.Errorf("failed to execute backend template: %w", err)
	}

	// Создаем terraform.tfvars.json из секций, которые нужно передать в Tofu
	// Например, spec.parameters и секреты
	tfvars := make(map[string]interface{})
	if params := k.Cut("spec.parameters"); params != nil {
		for key, val := range params.All() {
			tfvars[key] = val
		}
	}
	if creds := k.Cut("provider_credentials"); creds != nil {
		// Секреты тоже добавляем в переменные
		for key, val := range creds.All() {
			tfvars[key] = val
		}
	}

	tfvarsJSON, err := json.MarshalIndent(tfvars, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal tfvars to json: %w", err)
	}

	return os.WriteFile(filepath.Join(dir, "terraform.tfvars.json"), tfvarsJSON, 0o644)
}
