// File: cpc-go/cmd/ctx.go
package cmd

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// Структура для нашего простого конфигурационного файла
type cpcConfig struct {
	CurrentContext string `yaml:"current-context"`
}

var ctxCmd = &cobra.Command{
	Use:   "ctx [deployment-name]",
	Short: "Sets the active deployment context",
	Long: `Saves the specified deployment name as the current context.
Commands like 'plan' and 'apply' will use this context
if no deployment name is provided as an argument.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		deploymentName := args[0]

		homeDir, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("failed to get user home directory: %w", err)
		}

		configDir := filepath.Join(homeDir, ".cpc")
		if err := os.MkdirAll(configDir, 0o755); err != nil {
			return fmt.Errorf("failed to create config directory ~/.cpc: %w", err)
		}

		configPath := filepath.Join(configDir, "config.yaml")
		config := cpcConfig{CurrentContext: deploymentName}

		// Преобразуем структуру в YAML
		data, err := yaml.Marshal(&config)
		if err != nil {
			return fmt.Errorf("failed to marshal config to YAML: %w", err)
		}

		// Записываем в файл
		if err := os.WriteFile(configPath, data, 0o644); err != nil {
			return fmt.Errorf("failed to write to config file %s: %w", configPath, err)
		}

		log.Printf("✅ Context set to: %s", deploymentName)
		return nil
	},
}

func init() {
	// Добавляем команду 'ctx' в корень (cpc ctx)
	rootCmd.AddCommand(ctxCmd)
}
