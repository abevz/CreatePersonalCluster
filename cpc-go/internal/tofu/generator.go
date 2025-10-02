package tofu

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"strings"
	"text/template"

	"cpc-go/internal/config" // Импортируем наш пакет с конфигом
)

// HCLFiles - это карта, где ключ - имя файла (e.g., "main.tf"), а значение - его содержимое.
type HCLFiles map[string][]byte

// Generator - это наш главный генератор.
type Generator struct{}

// NewGenerator создает новый экземпляр генератора.
func NewGenerator() *Generator {
	return &Generator{}
}

// Generate принимает загруженную конфигурацию и создает HCL-файлы.
func (g *Generator) Generate(cfg *config.Deployment) (HCLFiles, error) {
	files := make(HCLFiles)

	// --- 1. Генерируем backend.tf ---
	backendContent, err := g.generateBackend(cfg)
	if err != nil {
		return nil, err
	}
	files["backend.tf"] = backendContent

	// --- 2. Генерируем providers.tf ---
	providersContent, err := g.generateProviders(cfg)
	if err != nil {
		return nil, err
	}
	files["providers.tf"] = providersContent

	// --- 3. Генерируем main.tf (ресурсы) ---
	mainContent, err := g.generateMain(cfg)
	if err != nil {
		return nil, err
	}
	files["main.tf"] = mainContent

	// --- 4. Генерируем terraform.tfvars.json (секреты) ---
	tfvarsContent, err := g.generateTfvars(cfg)
	if err != nil {
		return nil, err
	}
	files["terraform.tfvars.json"] = tfvarsContent

	log.Println("HCL-файлы успешно сгенерированы.")
	return files, nil
}

// --- Вспомогательные функции-генераторы ---

func (g *Generator) generateBackend(cfg *config.Deployment) ([]byte, error) {
	tmpl := `
terraform {
  backend "{{.Type}}" {
{{- range $key, $value := .Config }}
    {{ $key }} = "{{ $value }}"
{{- end }}
  }
}
`
	return g.executeTemplate("backend", tmpl, cfg.TofuBackend)
}

func (g *Generator) generateProviders(cfg *config.Deployment) ([]byte, error) {
	// Здесь мы могли бы добавить логику для разных провайдеров
	tmpl := `
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11" # Зафиксируем версию для стабильности
    }
  }
}

# Провайдер настраивается через переменные, которые мы передадим в .tfvars
provider "proxmox" {
  pm_api_url = var.proxmox_api_url
  pm_api_token_id = var.proxmox_token_id
  pm_api_token_secret = var.proxmox_token_secret
  pm_tls_insecure = true # Часто нужно для самоподписанных сертов
}
`
	return g.executeTemplate("providers", tmpl, nil)
}

func (g *Generator) generateMain(cfg *config.Deployment) ([]byte, error) {
	// Собираем все шаблоны ресурсов в один файл
	var mainSb strings.Builder

	// Шаблон для переменных
	varsTmpl := `
variable "proxmox_api_url" { type = string }
variable "proxmox_token_id" { type = string; sensitive = true }
variable "proxmox_token_secret" { type = string; sensitive = true }
`
	mainSb.WriteString(varsTmpl)

	// Преобразуем профили в карту для быстрого доступа
	profiles := make(map[string]config.InstanceProfile)
	for _, p := range cfg.Spec.InstanceProfiles {
		profiles[p.Name] = p
	}

	// Генерируем ресурсы для каждой группы нод
	for _, ng := range cfg.Spec.NodeGroups {
		profile, ok := profiles[ng.Profile]
		if !ok {
			return nil, fmt.Errorf("профиль '%s' не найден для группы нод '%s'", ng.Profile, ng.Name)
		}

		// Подготавливаем данные для шаблона
		data := struct {
			GroupName string
			Profile   config.InstanceProfile
			NodeGroup config.NodeGroup
		}{
			GroupName: ng.Name,
			Profile:   profile,
			NodeGroup: ng,
		}

		// Шаблон для ресурса VM
		vmTmpl := `
resource "proxmox_vm_qemu" "{{.GroupName}}" {
  count = {{.NodeGroup.Count}}
  name  = "{{.Profile.Name}}-${count.index + 1}"
  target_node = "{{.Profile.ProviderSettings.proxmox.node}}"

  clone = "{{.Profile.ProviderSettings.proxmox.template}}"
  
  cores = {{.Profile.Resources.CPU}}
  memory = {{.Profile.Resources.Memory | toMB }}
  
  disk {
    size    = "{{.Profile.Resources.Disk.Size}}"
    type    = "scsi"
    storage = "local-lvm" # Это можно будет вынести в конфиг
  }

  // Здесь можно добавить сетевые настройки и cloud-init
}
`
		// Добавляем к шаблону функции
		funcMap := template.FuncMap{
			"toMB": func(mem string) (int, error) {
				mem = strings.ToUpper(strings.TrimSpace(mem))
				if !strings.HasSuffix(mem, "GI") {
					return 0, fmt.Errorf("неподдерживаемый формат памяти: %s", mem)
				}
				val, err := strconv.Atoi(strings.TrimSuffix(mem, "GI"))
				if err != nil {
					return 0, err
				}
				return val * 1024, nil
			},
		}

		// Выполняем шаблон и добавляем результат в main.tf
		var renderedVM bytes.Buffer
		t, err := template.New("vm").Funcs(funcMap).Parse(vmTmpl)
		if err != nil {
			return nil, err
		}
		if err := t.Execute(&renderedVM, data); err != nil {
			return nil, err
		}
		mainSb.Write(renderedVM.Bytes())
	}

	return []byte(mainSb.String()), nil
}

func (g *Generator) generateTfvars(cfg *config.Deployment) ([]byte, error) {
	// Собираем все переменные, которые нужно передать в Tofu.
	// Ключи должны совпадать с 'variable' в HCL.
	tfvars := map[string]interface{}{
		"proxmox_api_url":      config.SanitizeURL(cfg.Spec.ProviderConfig.Proxmox["endpoint"]),
		"proxmox_token_id":     cfg.ProviderCredentials.Proxmox["token_id"],
		"proxmox_token_secret": cfg.ProviderCredentials.Proxmox["token_secret"],
	}

	return json.MarshalIndent(tfvars, "", "  ")
}

// executeTemplate - общая функция для выполнения Go-шаблонов.
func (g *Generator) executeTemplate(name, tmplStr string, data interface{}) ([]byte, error) {
	t, err := template.New(name).Parse(tmplStr)
	if err != nil {
		return nil, fmt.Errorf("ошибка парсинга шаблона '%s': %w", name, err)
	}

	var buf bytes.Buffer
	if err := t.Execute(&buf, data); err != nil {
		return nil, fmt.Errorf("ошибка выполнения шаблона '%s': %w", name, err)
	}

	return buf.Bytes(), nil
}
