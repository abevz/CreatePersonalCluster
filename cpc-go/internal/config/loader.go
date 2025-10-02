package config

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
	"go.mozilla.org/sops/v3/decrypt"
)

// sopsProvider - это кастомный провайдер для koanf, который
// "на лету" расшифровывает SOPS-файлы перед их парсингом.
type sopsProvider struct {
	path string
}

// ReadBytes читает и расшифровывает файл.
func (p *sopsProvider) ReadBytes() ([]byte, error) {
	// Расшифровываем файл, используя SOPS.
	// SOPS сам найдет .sops.yaml и определит, как расшифровывать (age, gpg, etc).
	decryptedData, err := decrypt.File(p.path, "yaml")
	if err != nil {
		return nil, fmt.Errorf("ошибка расшифровки SOPS файла '%s': %w", p.path, err)
	}
	return decryptedData, nil
}

// Read - обязательный метод интерфейса, который мы не используем напрямую.
func (p *sopsProvider) Read() (map[string]interface{}, error) {
	return nil, fmt.Errorf("sopsProvider не поддерживает Read(), используйте ReadBytes()")
}

// --- Основной загрузчик ---

var k = koanf.New(".")

// Load загружает, объединяет и парсит всю конфигурацию для развертывания.
func Load(deploymentPath string) (*Deployment, error) {
	// --- Шаг 1: Загрузка не-секретного deployment.yaml ---
	deploymentFile := filepath.Join(deploymentPath, "deployment.yaml")
	log.Printf("Загрузка файла декларации: %s", deploymentFile)
	if err := k.Load(file.Provider(deploymentFile), yaml.Parser()); err != nil {
		return nil, fmt.Errorf("ошибка загрузки deployment.yaml: %w", err)
	}

	// --- Шаг 2: Загрузка и расшифровка secrets.sops.yaml ---
	secretsFile := filepath.Join(deploymentPath, "secrets.sops.yaml")
	if _, err := os.Stat(secretsFile); err == nil {
		log.Printf("Загрузка и расшифровка файла секретов: %s", secretsFile)
		// Используем наш кастомный SOPS провайдер
		if err := k.Load(&sopsProvider{path: secretsFile}, yaml.Parser()); err != nil {
			return nil, fmt.Errorf("ошибка загрузки secrets.sops.yaml: %w", err)
		}
	} else {
		log.Printf("Файл секретов не найден, пропускаем: %s", secretsFile)
	}

	// --- Шаг 3: Парсинг объединенной конфигурации в нашу Go-структуру ---
	var cfg Deployment
	// Unmarshal разложит все ключи из koanf в структуру Deployment.
	if err := k.Unmarshal("", &cfg); err != nil {
		return nil, fmt.Errorf("ошибка парсинга конфигурации: %w", err)
	}

	// --- Шаг 4: Простая валидация (можно расширить) ---
	if cfg.Metadata.Name == "" {
		return nil, fmt.Errorf("metadata.name не может быть пустым")
	}
	if cfg.Spec.Provider == "" {
		return nil, fmt.Errorf("spec.provider не может быть пустым")
	}

	log.Printf("Конфигурация для '%s' успешно загружена.", cfg.Metadata.Name)
	return &cfg, nil
}

// SanitizeURL убирает обертку Markdown из URL, если она есть
func SanitizeURL(rawURL string) string {
	if strings.HasPrefix(rawURL, "[") && strings.Contains(rawURL, "](") {
		start := strings.Index(rawURL, "](")
		end := strings.LastIndex(rawURL, ")")
		if start != -1 && end != -1 {
			return rawURL[start+2 : end]
		}
	}
	return rawURL
}
