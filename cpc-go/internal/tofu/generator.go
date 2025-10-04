// File: internal/tofu/generator.go
package tofu

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"github.com/getsops/sops/v3"
	"github.com/getsops/sops/v3/aes"
	"github.com/getsops/sops/v3/cmd/sops/common"
	"github.com/getsops/sops/v3/decrypt"
	"github.com/getsops/sops/v3/keyservice"
	"github.com/getsops/sops/v3/stores/yaml"
	"github.com/getsops/sops/v3/version"
	go_yaml "gopkg.in/yaml.v3"
)

// GenerateFiles создает terraform.tfvars.json.
// Это твоя исходная функция, которая остается для генерации переменных.
func GenerateFiles(cfg *config.Deployment, workDir string) error {
	if err := generateTvars(cfg, workDir); err != nil {
		return fmt.Errorf("error generating terraform.tfvars.json: %w", err)
	}
	return nil
}

// --- НИЖЕ ИДЕТ НОВЫЙ КОД ДЛЯ РАБОТЫ С СЕКРЕТАМИ ---

// GenerateSecretsForTofu создает временный secrets.sops.yaml для OpenTofu,
// преобразуя новый формат секретов в старый.
func GenerateSecretsForTofu(cfg *config.Deployment, deploymentPath string, workDir string) error {
	// Эта функция вызывается только для старой схемы v1
	if cfg.Spec.TfvarsSchema != "" && cfg.Spec.TfvarsSchema != "v1" {
		log.Println("Skipping secrets transformation for non-v1 schema.")
		return nil
	}

	sourcePath := filepath.Join(deploymentPath, "secrets.sops.yaml")

	if _, err := os.Stat(sourcePath); os.IsNotExist(err) {
		log.Println("Source secrets.sops.yaml not found, skipping generation.")
		return nil
	}

	log.Println("Transforming secrets for OpenTofu...")

	// 1. Загружаем дерево, чтобы получить доступ к метаданным (KeyGroups).
	sourceBytes, err := os.ReadFile(sourcePath)
	if err != nil {
		return fmt.Errorf("could not read source secrets file %s: %w", sourcePath, err)
	}
	yamlStore := &yaml.Store{}
	originalTree, err := yamlStore.LoadEncryptedFile(sourceBytes)
	if err != nil {
		return fmt.Errorf("failed to load encrypted sops file '%s': %w", sourcePath, err)
	}

	// 2. Расшифровываем файл для получения чистого текста.
	decryptedYamlBytes, err := decrypt.File(sourcePath, "yaml")
	if err != nil {
		return fmt.Errorf("failed to decrypt sops file: %w", err)
	}

	// 3. Трансформируем данные в старый формат.
	var newSecrets map[string]interface{}
	if err := go_yaml.Unmarshal(decryptedYamlBytes, &newSecrets); err != nil {
		return fmt.Errorf("failed to unmarshal decrypted secrets YAML: %w", err)
	}
	legacySecretsMap := transformToLegacyFormat(newSecrets, cfg) // <--- Вот вызов недостающей функции
	legacyYamlBytes, err := go_yaml.Marshal(legacySecretsMap)
	if err != nil {
		return fmt.Errorf("failed to marshal legacy secrets map to YAML: %w", err)
	}

	// 4. Готовим новое дерево для шифрования, используя старые метаданные.
	branches, err := yamlStore.LoadPlainFile(legacyYamlBytes)
	if err != nil {
		return fmt.Errorf("error unmarshalling legacy data for re-encryption: %w", err)
	}

	reEncryptTree := sops.Tree{
		Branches: branches,
		Metadata: sops.Metadata{
			KeyGroups:       originalTree.Metadata.KeyGroups,
			Version:         version.Version,
			ShamirThreshold: originalTree.Metadata.ShamirThreshold,
		},
		FilePath: sourcePath,
	}

	// 5. Шифруем.
	dataKey, errs := reEncryptTree.GenerateDataKeyWithKeyServices([]keyservice.KeyServiceClient{keyservice.NewLocalClient()})
	if len(errs) > 0 {
		return fmt.Errorf("could not generate data key for re-encryption: %v", errs)
	}
	err = common.EncryptTree(common.EncryptTreeOpts{
		DataKey: dataKey,
		Tree:    &reEncryptTree,
		Cipher:  aes.NewCipher(),
	})
	if err != nil {
		return fmt.Errorf("could not encrypt tree: %w", err)
	}

	// 6. Сохраняем результат во временную директорию.
	encryptedFileBytes, err := yamlStore.EmitEncryptedFile(reEncryptTree)
	if err != nil {
		return fmt.Errorf("could not marshal final encrypted tree: %w", err)
	}

	destPath := filepath.Join(workDir, "secrets.sops.yaml")
	if err := os.WriteFile(destPath, encryptedFileBytes, 0o644); err != nil {
		return fmt.Errorf("failed to write final encrypted secrets file to '%s': %w", destPath, err)
	}

	log.Println("Successfully generated legacy secrets.sops.yaml for OpenTofu.")
	return nil
}

// transformToLegacyFormat - это вспомогательная функция, которая преобразует
// карту с секретами из нового формата в старый.
func transformToLegacyFormat(newSecrets map[string]interface{}, cfg *config.Deployment) map[string]interface{} {
	legacySecrets := make(map[string]interface{})

	// Provider Credentials (Proxmox)
	if creds, ok := newSecrets["provider_credentials"].(map[string]interface{}); ok {
		if proxmox, ok := creds["proxmox"].(map[string]interface{}); ok {
			legacySecrets["default.proxmox.username"] = proxmox["username"]
			legacySecrets["default.proxmox.password"] = proxmox["password"]
		}
	}
	if providerConfig, ok := cfg.Spec.ProviderConfig["proxmox"].(map[string]interface{}); ok {
		legacySecrets["default.proxmox.endpoint"] = providerConfig["endpoint"]
	}

	// S3 Backend Credentials
	if s3Creds, ok := newSecrets["s3_backend_credentials"].(map[string]interface{}); ok {
		legacySecrets["default.s3_backend.access_key"] = s3Creds["access_key"]
		legacySecrets["default.s3_backend.secret_key"] = s3Creds["secret_key"]
	}
	if cfg.TofuBackend.Type != "" && cfg.TofuBackend.Config != nil {
		legacySecrets["default.s3_backend.endpoint"] = cfg.TofuBackend.Config["endpoint"]
		legacySecrets["default.s3_backend.region"] = cfg.TofuBackend.Config["region"]
	}

	// Post-install secrets (for vm_ssh_keys and vm_password)
	if postInstall, ok := newSecrets["post_install_secrets"].(map[string]interface{}); ok {
		if pubKey, ok := postInstall["vm_ssh_public_key"].(string); ok {
			legacySecrets["vm_ssh_keys"] = []string{pubKey}
		}
		if vmCreds, ok := postInstall["vm_credentials"].(map[string]interface{}); ok {
			legacySecrets["vm_password"] = vmCreds["password"]
		}
	}
	return legacySecrets
}

// --- НИЖЕ ИДУТ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ИЗ ТВОЕГО ИСХОДНОГО ФАЙЛА ---

func generateTvars(cfg *config.Deployment, workDir string) error {
	var err error
	switch cfg.Spec.TfvarsSchema {
	case "v2":
		log.Println("Generating terraform.tfvars.json using new schema (v2)...")
		err = generateTfvarsV2(cfg, workDir)
	default:
		log.Println("Generating terraform.tfvars.json using legacy schema (v1)...")
		err = generateTfvarsV1(cfg, workDir)
	}
	if err != nil {
		return err
	}
	log.Println("File terraform.tfvars.json generated successfully.")
	return nil
}

func generateTfvarsV1(cfg *config.Deployment, workDir string) error {
	tfvars := make(map[string]interface{})

	tfvars["proxmox_password"] = cfg.ProviderCredentials.Proxmox["password"]
	if providerConfig, ok := cfg.Spec.ProviderConfig["proxmox"].(map[string]interface{}); ok {
		for key, val := range providerConfig {
			if key == "node" {
				tfvars["pm_node"] = val
			} else {
				tfvars["proxmox_"+key] = val
			}
		}
	}

	tfvars["cluster_id"] = cfg.Metadata.Name
	tfvars["cluster_domain"] = cfg.Spec.ClusterDomain

	if cfg.Spec.Variables != nil {
		for key, val := range cfg.Spec.Variables {
			tfvars[key] = val
		}
	}

	var additionalControlPlanes []string
	var additionalWorkers []string
	for _, group := range cfg.Spec.NodeGroups {
		baseCount := 0
		if group.Name == "control-plane" {
			baseCount = 1
		} else if group.Name == "workers" {
			baseCount = 2
		}
		if group.Count > baseCount {
			for i := baseCount + 1; i <= group.Count; i++ {
				singularName := strings.TrimSuffix(group.Name, "s")
				nodeName := fmt.Sprintf("%s-%d", singularName, i)
				if group.Name == "control-plane" {
					additionalControlPlanes = append(additionalControlPlanes, nodeName)
				} else if group.Name == "workers" {
					additionalWorkers = append(additionalWorkers, nodeName)
				}
			}
		}
	}
	tfvars["additional_controlplanes"] = strings.Join(additionalControlPlanes, ",")
	tfvars["additional_workers"] = strings.Join(additionalWorkers, ",")

	return writeTfvarsFile(tfvars, workDir)
}

func generateTfvarsV2(cfg *config.Deployment, workDir string) error {
	tfvars := make(map[string]interface{})
	tfvars["proxmox_password"] = cfg.ProviderCredentials.Proxmox["password"]
	if providerConfig, ok := cfg.Spec.ProviderConfig["proxmox"].(map[string]interface{}); ok {
		for key, val := range providerConfig {
			tfvars["proxmox_"+key] = val
		}
	}
	var allNodes []map[string]interface{}
	for _, group := range cfg.Spec.NodeGroups {
		for i := 1; i <= group.Count; i++ {
			node := make(map[string]interface{})
			node["name"] = fmt.Sprintf("%s-%d", group.Name, i)
			node["hostname"] = fmt.Sprintf("%s%d.%s", group.RolePrefix, i, cfg.Spec.ClusterDomain)
			node["role"] = group.Name
			node["profile"] = group.Profile
			allNodes = append(allNodes, node)
		}
	}
	tfvars["nodes"] = allNodes
	return writeTfvarsFile(tfvars, workDir)
}

func writeTfvarsFile(tfvars map[string]interface{}, workDir string) error {
	tfvarsJSON, err := json.MarshalIndent(tfvars, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal tfvars to JSON: %w", err)
	}
	return os.WriteFile(filepath.Join(workDir, "terraform.tfvars.json"), tfvarsJSON, 0o644)
}
