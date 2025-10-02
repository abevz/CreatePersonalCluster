// File: internal/config/loader.go
package config

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	// Используем официальную библиотеку SOPS
	"github.com/getsops/sops/v3/decrypt"

	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

// sopsProvider - это наш кастомный провайдер для koanf, который
// "на лету" расшифровывает SOPS-файлы перед их парсингом.
type sopsProvider struct {
	path string
}

// ReadBytes читает и расшифровывает файл. Это основной метод.
func (p *sopsProvider) ReadBytes() ([]byte, error) {
	// Вызываем напрямую функцию decrypt.File из библиотеки SOPS.
	// Она сама найдет .sops.yaml и разберется, как расшифровывать.
	decryptedData, err := decrypt.File(p.path, "yaml")
	if err != nil {
		return nil, fmt.Errorf("ошибка расшифровки SOPS файла '%s': %w", p.path, err)
	}
	return decryptedData, nil
}

// Read - обязательный метод интерфейса Provider, который мы не используем.
func (p *sopsProvider) Read() (map[string]interface{}, error) {
	// Koanf будет использовать ReadBytes(), поэтому этот метод можно оставить пустым.
	return nil, nil
}

// Load загружает и объединяет конфигурации.
// ПРИМЕЧАНИЕ: Структура Deployment должна быть определена в этом пакете или импортирована.
func Load(deploymentPath string) (*koanf.Koanf, error) {
	k := koanf.New(".")

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
		// Используем наш кастомный и надёжный SOPS провайдер
		if err := k.Load(&sopsProvider{path: secretsFile}, yaml.Parser()); err != nil {
			return nil, fmt.Errorf("ошибка загрузки secrets.sops.yaml: %w", err)
		}
	} else {
		log.Printf("Файл секретов не найден, пропускаем: %s", secretsFile)
	}

	log.Println("Конфигурация успешно загружена.")
	return k, nil
}
