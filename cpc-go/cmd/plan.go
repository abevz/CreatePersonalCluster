// File: cmd/plan.go
package cmd

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	// NEW: Added for printing file content
	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"github.com/abevz/createpersonalcluster/cpc-go/internal/tofu"
	"github.com/spf13/cobra"
)

// NEW: Variable to hold the value of our new flag
var (
	showGeneratedFiles bool
	planCmd            = &cobra.Command{
		Use:   "plan [deployment-name]",
		Short: "Shows a preview of infrastructure changes (dry-run)",
		Long: `Loads the configuration, generates HCL files for OpenTofu,
           and runs 'tofu plan' to show what changes will be applied to the
           infrastructure, without actually applying them.`,
		Args: cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			deploymentName := args[0]
			deploymentPath := filepath.Join(DeploymentsRoot, "deployments", deploymentName)
			log.Printf("Planning deployment for: %s", deploymentName)
			// --- Step 1: Load and parse configuration ---
			log.Println("-> Step 1/6: Loading configuration...")
			koanfObj, err := config.Load(deploymentPath)
			if err != nil {
				log.Fatalf("Error loading configuration: %v", err)
			}
			var cfg config.Deployment
			if err := koanfObj.Unmarshal("", &cfg); err != nil {
				log.Fatalf("Error unmarshalling configuration into struct: %v", err)
			}
			// --- Step 2: Create temporary work directory (NEW LOGIC) ---
			log.Println("-> Step 2/6: Creating temporary work directory...")
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
			// --- NEW Step 3: Copy Terraform files ---
			log.Println("-> Step 3/6: Copying .tf files to work directory...")
			if err := tofu.CopyTfFiles(TofuRoot, workDir); err != nil {
				log.Fatalf("Error copying .tf files: %v", err)
			}
			// --- Step 4: Generate HCL ---
			//
			log.Println("-> Step 4/6: Generating HCL files for OpenTofu...")
			if err := tofu.GenerateFiles(&cfg, workDir); err != nil {
				log.Fatalf("Error generating terraform.tfvars.json: %v", err)
			}
			if err := tofu.GenerateSecretsForTofu(&cfg, deploymentPath, workDir); err != nil {
				log.Fatalf("Error generating secrets for Tofu: %v", err)
			}
			// --- NEW Step 5: Generate and upload Cloud-Init Snippets ---
			//
			log.Println("-> Step 5/6: Generating Cloud-Init snippets...")
			// NEW: Pass the deploymentPath to the function
			if err := tofu.GenerateSnippets(&cfg, deploymentPath, workDir); err != nil {
				log.Fatalf("Error generating snippets: %v", err)
			}

			log.Println("   Uploading snippets to Proxmox...")
			if err := tofu.UploadSnippets(&cfg, workDir); err != nil {
				log.Fatalf("Error uploading snippets: %v", err)
			}

			// TODO: Add logic to upload the generated 'snippets' directory to Proxmox
			log.Println("   (Skipping snippet upload in 'plan' mode for now)")
			// NEW: Check if the debug flag is set
			if showGeneratedFiles {
				printGeneratedFiles(workDir)
			}
			// --- Step 4: Run Tofu Plan ---
			log.Println("-> Step 6/6: Running 'tofu plan'...")
			if err := tofu.Plan(workDir, &cfg); err != nil {
				log.Fatalf("Error executing 'tofu plan': %v", err)
			}
			log.Println("\n✅ Plan successfully generated.")
		},
	}
)

func printGeneratedFiles(workDir string) {
	fmt.Println("--- BEGIN Generated Files Content ---")
	// Walk through all files and subdirectories in the work directory
	err := filepath.Walk(workDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		// We only want to print files, not directories
		if !info.IsDir() {
			// Read the file content
			content, readErr := os.ReadFile(path)
			if readErr != nil {
				log.Printf("   Could not read file %s: %v", path, readErr)
				return nil // Continue walking
			}
			// Print file path and its content
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

// NEW: Helper function to print the content of generated files
func init() {
	// NEW: Add the flag to the 'plan' command
	planCmd.Flags().BoolVar(&showGeneratedFiles, "show-generated-files", false, "Print the content of generated Tofu files for debugging")
	deploymentCmd.AddCommand(planCmd)
}
