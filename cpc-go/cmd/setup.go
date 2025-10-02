package cmd

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/huh"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/templates"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// setupAnswers holds the user's answers from the interactive setup wizard.
type setupAnswers struct {
	DeploymentsRoot string
	TofuPath        string
	AnsiblePath     string
	AgeKeyFile      string
	CreateProxmox   bool
	CreateAWS       bool
}

// globalConfig defines the structure of the global ~/.config/cpc/config.yaml file.
type globalConfig struct {
	DeploymentsRoot string `yaml:"deployments_root"`
	Paths           struct {
		Tofu    string `yaml:"tofu"`
		Ansible string `yaml:"ansible"`
	} `yaml:"paths"`
	SOPS struct {
		AgeKeyFile string `yaml:"age_key_file"`
	} `yaml:"sops"`
}

// setupCmd represents the setup command.
var setupCmd = &cobra.Command{
	Use:   "setup",
	Short: "Interactive setup for the first-time use of cpc-go",
	Long: `This command runs a step-by-step wizard that helps you
configure global settings, specify the path to your deployment
configurations, and create initial templates.`,
	Run: func(cmd *cobra.Command, args []string) {
		answers, err := runSetupWizard()
		if err != nil {
			if err == huh.ErrUserAborted {
				log.Println("Setup wizard aborted by user.")
				os.Exit(0)
			}
			log.Fatalf("Setup wizard failed: %v", err)
		}

		if err := saveGlobalConfig(answers); err != nil {
			log.Fatalf("Failed to save global config: %v", err)
		}

		if err := createTemplateDeployments(answers); err != nil {
			log.Fatalf("Failed to create deployment templates: %v", err)
		}

		fmt.Println("\n✅ Setup completed successfully!")
		fmt.Printf("Global configuration file saved to ~/.config/cpc/config.yaml\n")
		fmt.Printf("You can now navigate to %s and start working.\n", answers.DeploymentsRoot)
	},
}

// runSetupWizard runs the interactive prompt session to gather user settings.
func runSetupWizard() (*setupAnswers, error) {
	answers := &setupAnswers{}

	// Auto-detect paths for common tools.
	tofuPath, _ := exec.LookPath("tofu")
	ansiblePath, _ := exec.LookPath("ansible-playbook")

	// Set default values before running the form.
	// `huh` will use these as the initial values for the fields.
	answers.DeploymentsRoot = "~/cpc-deployments"
	answers.TofuPath = tofuPath
	answers.AnsiblePath = ansiblePath
	answers.AgeKeyFile = "~/.config/sops/age/keys.txt"

	// Create the form using huh.
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Enter the path to your Git repository for deployment configs:").
				Description("This is the root folder where a 'deployments' directory will be created. You can use '~'.").
				Value(&answers.DeploymentsRoot).
				Validate(func(s string) error {
					if s == "" {
						return fmt.Errorf("path cannot be empty")
					}
					return nil
				}),

			huh.NewInput().
				Title("Path to the 'tofu' executable:").
				Value(&answers.TofuPath).
				Validate(func(s string) error {
					if s == "" {
						return fmt.Errorf("path cannot be empty")
					}
					return nil
				}),

			huh.NewInput().
				Title("Path to the 'ansible-playbook' executable:").
				Value(&answers.AnsiblePath),

			huh.NewInput().
				Title("Path to your private 'age' key for SOPS:").
				Description("If you don't have a key, leave this empty, and we will guide you to generate one.").
				Value(&answers.AgeKeyFile),
		),

		huh.NewGroup(
			huh.NewConfirm().
				Title("Create an example/template for a Proxmox deployment?").
				Value(&answers.CreateProxmox),

			huh.NewConfirm().
				Title("Create an example/template for an AWS deployment?").
				Value(&answers.CreateAWS),
		),
	)

	err := form.Run()
	if err != nil {
		return nil, err
	}

	// Handle age key generation guidance.
	if answers.AgeKeyFile == "" {
		fmt.Println("\nAge key file not specified. Let's generate a new one.")
		fmt.Println("Please run the command `age-keygen -o age.key`")
		fmt.Println("The public key will be printed to the console. Save it.")
		fmt.Println("Then, provide the path to `age.key` the next time you run `setup`.")
	}

	return answers, nil
}

// expandPath is a helper function to replace ~ with the user's home directory.
func expandPath(path string) (string, error) {
	if !strings.HasPrefix(path, "~") {
		return path, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, path[1:]), nil
}

// saveGlobalConfig saves the collected answers to the global config file.
func saveGlobalConfig(answers *setupAnswers) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	configDir := filepath.Join(home, ".config", "cpc")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return err
	}
	configPath := filepath.Join(configDir, "config.yaml")

	deploymentsRoot, err := expandPath(answers.DeploymentsRoot)
	if err != nil {
		return err
	}
	ageKeyFile, err := expandPath(answers.AgeKeyFile)
	if err != nil {
		return err
	}

	cfg := globalConfig{
		DeploymentsRoot: deploymentsRoot,
		Paths: struct {
			Tofu    string `yaml:"tofu"`
			Ansible string `yaml:"ansible"`
		}{
			Tofu:    answers.TofuPath,
			Ansible: answers.AnsiblePath,
		},
		SOPS: struct {
			AgeKeyFile string `yaml:"age_key_file"`
		}{
			AgeKeyFile: ageKeyFile,
		},
	}

	data, err := yaml.Marshal(&cfg)
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0o644)
}

// createTemplateDeployments creates the example deployment directories and files.
func createTemplateDeployments(answers *setupAnswers) error {
	rootPath, err := expandPath(answers.DeploymentsRoot)
	if err != nil {
		return err
	}

	if answers.CreateProxmox {
		path := filepath.Join(rootPath, "deployments", "proxmox-k8s-example")
		if err := createDeploymentTemplate(path, templates.ProxmoxDeployment, templates.ProxmoxSecrets); err != nil {
			return fmt.Errorf("error creating Proxmox template: %w", err)
		}
		fmt.Printf("✓ Proxmox template created at: %s\n", path)
	}

	if answers.CreateAWS {
		path := filepath.Join(rootPath, "deployments", "aws-eks-example")
		if err := createDeploymentTemplate(path, templates.AWSDeployment, templates.AWSSecrets); err != nil {
			return fmt.Errorf("error creating AWS template: %w", err)
		}
		fmt.Printf("✓ AWS template created at: %s\n", path)
	}

	return nil
}

// createDeploymentTemplate is a helper to write the template files to disk.
func createDeploymentTemplate(path, deploymentContent, secretsContent string) error {
	if err := os.MkdirAll(path, 0o755); err != nil {
		return err
	}

	if err := os.WriteFile(filepath.Join(path, "deployment.yaml"), []byte(deploymentContent), 0o644); err != nil {
		return err
	}

	secretsContentWithNote := "# WARNING: This file contains unencrypted secrets.\n" +
		"# Edit it with your values and encrypt it using the command:\n" +
		"# sops --encrypt --in-place secrets.sops.yaml\n\n" +
		secretsContent
	if err := os.WriteFile(filepath.Join(path, "secrets.sops.yaml"), []byte(secretsContentWithNote), 0o644); err != nil {
		return err
	}
	return nil
}

func init() {
	rootCmd.AddCommand(setupCmd)
}
