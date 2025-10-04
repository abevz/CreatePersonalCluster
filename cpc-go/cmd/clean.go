// File: cpc-go/cmd/clean.go
package cmd

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var (
	// Переменная для хранения значения флага --older-than
	olderThan string

	cleanRunsCmd = &cobra.Command{
		Use:   "clean-runs",
		Short: "Cleans up temporary run directories",
		Long: `Removes temporary directories created during 'plan' or 'apply' operations.
By default, it removes all 'cpc-run-*' directories. Use the --older-than flag
to remove only directories older than a specified duration.
Examples:
  cpc deployment clean-runs
  cpc deployment clean-runs --older-than 7d  (deletes runs older than 7 days)
  cpc deployment clean-runs --older-than 48h (deletes runs older than 48 hours)`,
		RunE: func(cmd *cobra.Command, args []string) error {
			homeDir, err := os.UserHomeDir()
			if err != nil {
				return fmt.Errorf("failed to get user home directory: %w", err)
			}

			runsDir := filepath.Join(homeDir, ".cpc", "runs")

			// Проверяем, существует ли директория
			if _, err := os.Stat(runsDir); os.IsNotExist(err) {
				log.Println("✅ Runs directory ~/.cpc/runs does not exist. Nothing to clean.")
				return nil
			}

			// Читаем содержимое директории
			entries, err := os.ReadDir(runsDir)
			if err != nil {
				return fmt.Errorf("failed to read runs directory %s: %w", runsDir, err)
			}

			var cutoffTime time.Time
			// Если флаг --older-than был использован, вычисляем пороговое время
			if olderThan != "" {
				duration, err := parseDuration(olderThan)
				if err != nil {
					return fmt.Errorf("invalid duration format for --older-than: %w", err)
				}
				cutoffTime = time.Now().Add(-duration)
				log.Printf("Looking for runs older than %s (created before %s)...", olderThan, cutoffTime.Format(time.RFC822))
			} else {
				log.Println("Looking for all 'cpc-run-*' directories to clean...")
			}

			deletedCount := 0
			for _, entry := range entries {
				// Нас интересуют только директории, начинающиеся с 'cpc-run-'
				if entry.IsDir() && strings.HasPrefix(entry.Name(), "cpc-run-") {
					fullPath := filepath.Join(runsDir, entry.Name())
					info, err := entry.Info()
					if err != nil {
						log.Printf("Could not get info for %s, skipping: %v", entry.Name(), err)
						continue
					}

					// Если cutoffTime не установлена (флаг не использовался), удаляем сразу.
					// Иначе, проверяем время модификации.
					if cutoffTime.IsZero() || info.ModTime().Before(cutoffTime) {
						log.Printf("   -> Deleting %s", fullPath)
						if err := os.RemoveAll(fullPath); err != nil {
							log.Printf("      Error deleting directory: %v", err)
						} else {
							deletedCount++
						}
					}
				}
			}

			if deletedCount > 0 {
				log.Printf("\n✅ Successfully deleted %d run director(y/ies).", deletedCount)
			} else {
				log.Println("\n✅ No matching run directories found to clean.")
			}

			return nil
		},
	}
)

// parseDuration - это вспомогательная функция для разбора строк вроде "7d", "48h".
// Стандартная time.ParseDuration не поддерживает дни ('d').
func parseDuration(s string) (time.Duration, error) {
	s = strings.ToLower(s)
	if strings.HasSuffix(s, "d") {
		daysStr := strings.TrimSuffix(s, "d")
		days, err := strconv.Atoi(daysStr)
		if err != nil {
			return 0, err
		}
		// Конвертируем дни в часы для time.ParseDuration
		return time.ParseDuration(fmt.Sprintf("%dh", days*24))
	}
	// Для других единиц (h, m, s) используем стандартный парсер
	return time.ParseDuration(s)
}

func init() {
	// Добавляем флаг --older-than
	cleanRunsCmd.Flags().StringVar(&olderThan, "older-than", "", "Clean up runs older than a specified duration (e.g., 7d, 48h, 30m)")
	// Добавляем новую команду 'clean-runs' в родительскую команду 'deployment'
	deploymentCmd.AddCommand(cleanRunsCmd)
}
