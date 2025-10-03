// File: cmd/deployment.go
package cmd

import (
	"github.com/spf13/cobra"
)

// deploymentCmd представляет родительскую команду `deployment`
var deploymentCmd = &cobra.Command{
	Use:   "deployment",
	Short: "Управление развертываниями кластера (plan, apply, config)",
}

// Единая точка регистрации для всех подкоманд deployment
func init() {
	// Присоединяем deployment к корневой команде
	rootCmd.AddCommand(deploymentCmd)

	// А теперь к deployment присоединяем все его дочерние команды
	deploymentCmd.AddCommand(configCmd) // из config.go
	deploymentCmd.AddCommand(planCmd)   // из plan.go
	deploymentCmd.AddCommand(applyCmd)  // из apply.go
}
