// File: cmd/deployment.go
package cmd

import (
	"fmt"
	"log"
	"os"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"github.com/abevz/createpersonalcluster/cpc-go/internal/tofu"

	"github.com/spf13/cobra"
)

var deploymentCmd = &cobra.Command{
	Use:   "deployment",
	Short: "Manage cluster deployments",
}

var applyCmd = &cobra.Command{
	Use:   "apply",
	Short: "Apply the deployment configuration to create/update infrastructure",
	Run: func(cmd *cobra.Command, args []string) {
		// 1. Загрузка Конфигурации
		fmt.Println("🔄 [1/6] Loading configurations...")
		cfg, err := config.Load(".")
		if err != nil {
			log.Fatalf("Error loading config: %v", err)
		}

		// 2. Создание Контекста (Временная директория)
		fmt.Println("📁 [2/6] Creating temporary work directory...")
		workDir, err := os.MkdirTemp("", "cpc-run-*")
		if err != nil {
			log.Fatalf("Failed to create temp dir: %v", err)
		}
		defer os.RemoveAll(workDir)
		fmt.Printf("   -> Directory created: %s\n", workDir)

		// 3. Генерация HCL
		fmt.Println("📝 [3/6] Generating OpenTofu HCL files...")
		err = tofu.GenerateHCL(cfg, workDir)
		if err != nil {
			log.Fatalf("Failed to generate HCL: %v", err)
		}

		// 4. Запуск Tofu
		fmt.Println("🚀 [4/6] Running OpenTofu...")
		outputs, err := tofu.Execute(workDir)
		if err != nil {
			log.Fatalf("OpenTofu execution failed: %v", err)
		}

		// 5. Запуск Задач (Ansible)
		fmt.Println("🔧 [5/6] Running post-create tasks...")
		// Здесь будет логика для парсинга outputs и запуска Ansible
		// Для примера просто выведем outputs
		fmt.Println("   -> Tofu outputs received:")
		for key, val := range outputs {
			// В реальном коде здесь будет парсинг IP
			fmt.Printf("      - %s: %v\n", key, val)
		}

		// 6. Очистка
		fmt.Println("🧹 [6/6] Cleaning up...")
		// defer os.RemoveAll(workDir) сработает здесь

		fmt.Println("\n✨ Deployment applied successfully! ✨")
	},
}

func init() {
	rootCmd.AddCommand(deploymentCmd)
	deploymentCmd.AddCommand(configCmd)
	deploymentCmd.AddCommand(applyCmd)
}
