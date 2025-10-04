// File: cmd/apply.go
package cmd

import (
	"log"
	"os"
	"path/filepath"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"github.com/abevz/createpersonalcluster/cpc-go/internal/tofu"
	"github.com/spf13/cobra"
)

var applyCmd = &cobra.Command{
	Use:   "apply [deployment-name]",
	Short: "Применяет конфигурацию для создания/обновления инфраструктуры",
	Long:  `Полный цикл: загрузка конфига, генерация HCL, запуск 'tofu apply' и выполнение задач после создания.`,
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		deploymentName := args[0]
		deploymentPath := filepath.Join(DeploymentsRoot, "deployments", deploymentName)

		log.Printf("Применение развертывания: %s", deploymentName)

		// --- Шаг 1: Загрузка и парсинг конфигурации ---
		log.Println("-> Шаг 1/5: Загрузка конфигурации...")
		koanfObj, err := config.Load(deploymentPath)
		if err != nil {
			log.Fatalf("Ошибка загрузки конфигурации: %v", err)
		}
		var cfg config.Deployment
		if err := koanfObj.Unmarshal("", &cfg); err != nil {
			log.Fatalf("Ошибка парсинга конфигурации в структуру: %v", err)
		}

		// --- Step 2: Create temporary work directory (NEW LOGIC) ---
		log.Println("-> Step 2/5: Creating temporary work directory...")
		homeDir, err := os.UserHomeDir()
		if err != nil {
			log.Fatalf("Failed to get user home directory: %v", err)
		}
		// Create a subdirectory in the user's home directory
		runsDir := filepath.Join(homeDir, ".cpc", "runs")
		if err := os.MkdirAll(runsDir, 0o755); err != nil {
			log.Fatalf("Failed to create runs directory: %v", err)
		}
		workDir, err := os.MkdirTemp(runsDir, "cpc-run-*")
		if err != nil {
			log.Fatalf("Failed to create temp directory in ~/.cpc/runs: %v", err)
		}
		defer os.RemoveAll(workDir)
		log.Printf("   Work directory created: %s", workDir)

		// --- Шаг 3: Генерация HCL ---
		log.Println("-> Шаг 3/5: Генерация HCL-файлов для OpenTofu...")
		if err := tofu.GenerateFiles(&cfg, workDir); err != nil {
			log.Fatalf("Ошибка генерации HCL: %v", err)
		}

		// --- Шаг 4: Запуск Tofu Apply ---
		log.Println("-> Шаг 4/5: Запуск 'tofu apply'...")
		outputs, err := tofu.Apply(workDir, &cfg)
		if err != nil {
			log.Fatalf("Ошибка выполнения 'tofu apply': %v", err)
		}

		// --- Шаг 5: Запуск Ansible ---
		log.Println("-> Шаг 5/5: Запуск задач после развертывания...")
		// TODO: Добавить логику вызова Ansible с передачей `outputs`
		log.Printf("   Выходные данные Tofu: %v", outputs)

		log.Println("\n✅ Развертывание успешно применено!")
	},
}
