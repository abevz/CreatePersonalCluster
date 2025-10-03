package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
	"github.com/spf13/cobra"
)

var (
	globalCfgFile   string
	DeploymentsRoot string
	k               = koanf.New(".")
)

var TofuRoot string

var rootCmd = &cobra.Command{
	Use:   "cpc-go",
	Short: "CPC-GO is an orchestrator for your infrastructure.",
	Long: `A tool that uses a declarative approach to create,
manage, and destroy infrastructure across various cloud and on-premise providers.`,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if err := loadGlobalConfig(); err != nil {
			return err
		}

		var deploymentsPath string
		userPath, _ := cmd.Flags().GetString("deployments-root")
		if userPath != "" {
			deploymentsPath = userPath
		} else {
			deploymentsPath = k.String("deployments_root")
		}

		if deploymentsPath == "" {
			deploymentsPath = "."
		}

		// Replace tilde '~' with the user's home directory using the standard library.
		if strings.HasPrefix(deploymentsPath, "~/") {
			home, err := os.UserHomeDir()
			if err != nil {
				return fmt.Errorf("could not get user home directory: %w", err)
			}
			deploymentsPath = filepath.Join(home, deploymentsPath[2:])
		}

		var err error
		DeploymentsRoot, err = filepath.Abs(deploymentsPath)
		if err != nil {
			return fmt.Errorf("could not get absolute path for '%s': %w", deploymentsPath, err)
		}

		fmt.Printf("Deployments root: %s\n", DeploymentsRoot)
		return nil
	},
}

func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&globalCfgFile, "config", "", "Path to global config file (default is ~/.config/cpc/config.yaml)")
	rootCmd.PersistentFlags().String("deployments-root", "", "Root directory for deployments (overrides value in config.yaml)")
	rootCmd.PersistentFlags().StringVar(&TofuRoot, "tofu-root", "../terraform", "Root directory for OpenTofu .tf files")
}

func loadGlobalConfig() error {
	if globalCfgFile != "" {
		if err := k.Load(file.Provider(globalCfgFile), yaml.Parser()); err != nil {
			return fmt.Errorf("error loading specified config file: %w", err)
		}
		return nil
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("could not find home directory: %w", err)
	}
	defaultCfgPath := filepath.Join(home, ".config", "cpc", "config.yaml")

	if _, err := os.Stat(defaultCfgPath); err == nil {
		if err := k.Load(file.Provider(defaultCfgPath), yaml.Parser()); err != nil {
			return fmt.Errorf("error loading default config file: %w", err)
		}
	}

	return nil
}
