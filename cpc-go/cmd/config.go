// File: cmd/config.go
package cmd

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"github.com/jedib0t/go-pretty/v6/table"
	"github.com/spf13/cobra"
)

// configCmd представляет команду `deployment config`
var configCmd = &cobra.Command{
	Use:   "config [deployment-name]",
	Short: "Показывает объединенную конфигурацию для развертывания в виде таблицы",
	Long: `Загружает, расшифровывает и объединяет все конфигурационные файлы
(глобальный, deployment.yaml и secrets.sops.yaml) и выводит результат
в удобном для чтения табличном формате.

Секретные значения будут автоматически скрыты.
Эта команда идеально подходит для отладки и проверки конфигурации.`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		deploymentName := args[0]
		deploymentPath := filepath.Join(DeploymentsRoot, "deployments", deploymentName)

		log.Printf("Загрузка конфигурации из: %s", deploymentPath)
		if _, err := os.Stat(deploymentPath); os.IsNotExist(err) {
			log.Fatalf("Ошибка: директория развертывания '%s' не найдена.", deploymentPath)
		}

		// Шаг 1: Загружаем конфигурацию в сырой объект koanf.
		koanfObj, err := config.Load(deploymentPath)
		if err != nil {
			log.Fatalf("Ошибка: не удалось загрузить конфигурацию: %v", err)
		}

		// Шаг 2: Объявляем переменную для нашей структуры.
		var deploymentData config.Deployment

		// Шаг 3: "Перекладываем" данные из объекта koanf в нашу структуру.
		if err := koanfObj.Unmarshal("", &deploymentData); err != nil {
			log.Fatalf("Ошибка парсинга конфигурации в структуру: %v", err)
		}

		log.Printf("Конфигурация успешно смаплена в структуру.")

		// --- Логика вывода в таблицу ---
		t := table.NewWriter()
		t.SetOutputMirror(os.Stdout)
		t.SetStyle(table.StyleRounded)
		t.SetTitle("Объединенная Конфигурация для '%s'", deploymentName)
		t.AppendHeader(table.Row{"Ключ Конфигурации", "Значение"})

		// Шаг 4: Передаем в рендер ПРАВИЛЬНУЮ, заполненную структуру.
		appendStructToTable(t, reflect.ValueOf(deploymentData), "")

		t.Render()
	},
}

// appendStructToTable рекурсивно "разворачивает" структуру для таблицы.
func appendStructToTable(t table.Writer, val reflect.Value, prefix string) {
	if val.Kind() == reflect.Ptr {
		val = val.Elem()
	}
	if val.Kind() != reflect.Struct {
		return
	}

	for i := 0; i < val.NumField(); i++ {
		field := val.Field(i)
		fieldType := val.Type().Field(i)

		// ИСПРАВЛЕНИЕ: Ищем правильный тег "koanf", а не "mapstructure".
		keyName := fieldType.Tag.Get("koanf")
		if keyName == "" {
			continue // Пропускаем поля без тега
		}

		fullKey := keyName
		if prefix != "" {
			fullKey = prefix + "." + keyName
		}

		switch field.Kind() {
		case reflect.Struct:
			appendStructToTable(t, field, fullKey)
		case reflect.Map:
			for _, key := range field.MapKeys() {
				mapValue := field.MapIndex(key)
				rowKey := fullKey + "." + fmt.Sprintf("%v", key.Interface())
				t.AppendRow(table.Row{rowKey, formatValue(rowKey, mapValue)})
			}
		default:
			t.AppendRow(table.Row{fullKey, formatValue(fullKey, field)})
		}
	}
}

// formatValue форматирует значение для вывода и скрывает секреты.
func formatValue(key string, v reflect.Value) string {
	if containsSensitiveKeyword(key) {
		return "*** SENSITIVE ***"
	}
	if v.Kind() == reflect.Ptr && !v.IsNil() {
		v = v.Elem()
	}
	return fmt.Sprintf("%v", v.Interface())
}

// containsSensitiveKeyword проверяет, содержит ли ключ "секретные" слова.
func containsSensitiveKeyword(key string) bool {
	sensitiveWords := []string{"credentials", "secret", "token", "password", "private_key"}
	for _, word := range sensitiveWords {
		if strings.Contains(strings.ToLower(key), word) {
			return true
		}
	}
	return false
}

func init() {
	deploymentCmd.AddCommand(configCmd)
}
