// File: cmd/plan.go
package cmd

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"github.com/abevz/createpersonalcluster/cpc-go/internal/tofu"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

var (
	showGeneratedFiles bool
	// НОВЫЙ флаг для сохранения директории
	debugDir bool
	planCmd  = &cobra.Command{
		Use:   "plan [deployment-name]",
		Short: "Shows a preview of infrastructure changes (dry-run)",
		Long: `Loads the configuration, generates HCL files for OpenTofu,
           and runs 'tofu plan' to show what changes will be applied to the
           infrastructure, without actually applying them.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			var deploymentName string
			var err error

			// НОВАЯ ЛОГИКА: определяем имя деплоймента
			if len(args) == 0 {
				// Если аргументов нет, читаем из контекста
				deploymentName, err = getCurrentContext()
				if err != nil {
					return err
				}
				log.Printf("Using context: %s", deploymentName)
			} else {
				// Если аргумент есть, используем его
				deploymentName = args[0]
			}

			deploymentPath := filepath.Join(DeploymentsRoot, "deployments", deploymentName)
			log.Printf("Planning deployment for: %s", deploymentName)

			// --- Step 1: Load and parse configuration ---
			log.Println("-> Step 1/6: Loading configuration...")
			koanfObj, err := config.Load(deploymentPath)
			if err != nil {
				return fmt.Errorf("error loading configuration: %w", err)
			}
			var cfg config.Deployment
			if err := koanfObj.Unmarshal("", &cfg); err != nil {
				return fmt.Errorf("error unmarshalling configuration into struct: %w", err)
			}

			// --- Step 2: Create work directory (НОВАЯ ЛОГИКА) ---
			log.Println("-> Step 2/6: Creating work directory...")
			homeDir, err := os.UserHomeDir()
			if err != nil {
				return fmt.Errorf("failed to get user home directory: %w", err)
			}
			runsDir := filepath.Join(homeDir, ".cpc", "runs")
			var workDir string // Объявляем workDir здесь

			if debugDir {
				// Логика для постоянной директории
				workDir = filepath.Join(runsDir, deploymentName)
				log.Printf("   Debug mode enabled. Using persistent directory: %s", workDir)
				// Удаляем предыдущее содержимое, если оно есть, для чистого запуска
				if err := os.RemoveAll(workDir); err != nil {
					return fmt.Errorf("failed to clean persistent directory %s: %w", workDir, err)
				}
				if err := os.MkdirAll(workDir, 0o755); err != nil {
					return fmt.Errorf("failed to create persistent directory %s: %w", workDir, err)
				}
			} else {
				// Логика для временной директории (как и раньше)
				if err := os.MkdirAll(runsDir, 0o755); err != nil {
					return fmt.Errorf("failed to create runs directory: %w", err)
				}
				workDir, err = os.MkdirTemp(runsDir, "cpc-run-*")
				if err != nil {
					return fmt.Errorf("failed to create temp directory in ~/.cpc/runs: %w", err)
				}
				// Удаляем директорию только если она временная
				defer os.RemoveAll(workDir)
				log.Printf("   Work directory created: %s", workDir)
			}

			// --- Step 3: Copy Terraform files ---
			log.Println("-> Step 3/6: Copying .tf files to work directory...")
			if err := tofu.CopyTfFiles(TofuRoot, workDir); err != nil {
				return fmt.Errorf("error copying .tf files: %w", err)
			}

			// --- Step 4: Generate HCL ---
			log.Println("-> Step 4/6: Generating HCL files for OpenTofu...")
			if err := tofu.GenerateFiles(&cfg, workDir); err != nil {
				return fmt.Errorf("error generating terraform.tfvars.json: %w", err)
			}
			if err := tofu.GenerateSecretsForTofu(&cfg, deploymentPath, workDir); err != nil {
				return fmt.Errorf("error generating secrets for Tofu: %w", err)
			}

			// --- Step 5: Generate and upload Cloud-Init Snippets ---
			log.Println("-> Step 5/6: Generating Cloud-Init snippets...")
			if err := tofu.GenerateSnippets(&cfg, deploymentPath, workDir); err != nil {
				return fmt.Errorf("error generating snippets: %w", err)
			}

			log.Println("   Uploading snippets to Proxmox...")
			if err := tofu.UploadSnippets(&cfg, workDir); err != nil {
				return fmt.Errorf("error uploading snippets: %w", err)
			}

			log.Println("   (Skipping snippet upload in 'plan' mode for now)")
			if showGeneratedFiles {
				printGeneratedFiles(workDir)
			}

			// --- Step 6: Run Tofu Plan ---
			log.Println("-> Step 6/6: Running 'tofu plan'...")
			if err := tofu.Plan(workDir, &cfg); err != nil {
				return fmt.Errorf("error executing 'tofu plan': %w", err)
			}

			log.Println("\n✅ Plan successfully generated.")
			if debugDir {
				log.Printf("💡 The work directory has been preserved for debugging at: %s", workDir)
			}
			return nil
		},
	}
)

func getCurrentContext() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get user home directory: %w", err)
	}
	configPath := filepath.Join(homeDir, ".cpc", "config.yaml")

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return "", fmt.Errorf("no context set. Please run 'cpc ctx <deployment-name>' or provide a deployment name")
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return "", fmt.Errorf("failed to read config file %s: %w", configPath, err)
	}

	var config cpcConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return "", fmt.Errorf("failed to unmarshal config file: %w", err)
	}

	if config.CurrentContext == "" {
		return "", fmt.Errorf("current-context is not set in %s", configPath)
	}

	return config.CurrentContext, nil
}

func printGeneratedFiles(workDir string) {
	// ... (эта функция остается без изменений)
	fmt.Println("--- BEGIN Generated Files Content ---")
	err := filepath.Walk(workDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			content, readErr := os.ReadFile(path)
			if readErr != nil {
				log.Printf("   Could not read file %s: %v", path, readErr)
				return nil
			}
			fmt.Printf("\n--- File: %s ---\n", path)
			fmt.Println(string(content))
		}
		return nil
	})
	if err != nil {
		log.Printf("Error walking through generated files: %v", err)
	}
	fmt.Println("--- END Generated Files Content ---")
}

func init() {
	planCmd.Flags().BoolVar(&showGeneratedFiles, "show-generated-files", false, "Print the content of generated Tofu files for debugging")
	// Добавляем новый флаг
	planCmd.Flags().BoolVar(&debugDir, "debug-dir", false, "Keep the temporary run directory for debugging")
	deploymentCmd.AddCommand(planCmd)
}
