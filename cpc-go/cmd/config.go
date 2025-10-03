// File: cmd/config.go
package cmd

import (
	"encoding/json" // ИЗМЕНЕНИЕ: Импортируем для красивого вывода JSON
	"fmt"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"unicode/utf8" // ИЗМЕНЕНИЕ: Импортируем для работы со строками

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

		koanfObj, err := config.Load(deploymentPath)
		if err != nil {
			log.Fatalf("Ошибка: не удалось загрузить конфигурацию: %v", err)
		}

		var deploymentData config.Deployment
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

		// ИЗМЕНЕНИЕ: Настраиваем колонки для переноса текста
		t.SetColumnConfigs([]table.ColumnConfig{
			{Number: 1, AutoMerge: true}, // Колонка с ключами
			{Number: 2, WidthMax: 80},    // Колонка со значениями, макс. ширина 80 символов
		})

		appendStructToTable(t, reflect.ValueOf(deploymentData), "")

		t.Render()
	},
}

// ... (функция appendStructToTable остается без изменений) ...
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
		keyName := fieldType.Tag.Get("koanf")
		if keyName == "" {
			continue
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

// ИЗМЕНЕНИЕ: Полностью переписанная функция formatValue для красоты
func formatValue(key string, v reflect.Value) string {
	if containsSensitiveKeyword(key) {
		return "*** SENSITIVE ***"
	}

	if v.Kind() == reflect.Ptr && !v.IsNil() {
		v = v.Elem()
	}

	// Получаем интерфейс для дальнейшей работы
	val := v.Interface()

	// Специальная обработка для приватного ключа
	if key == "post_install_secrets.vm_ssh_private_key" {
		if s, ok := val.(string); ok && utf8.RuneCountInString(s) > 60 {
			return s[:30] + "\n[...обрезано...]\n" + s[len(s)-30:]
		}
	}

	// Красивый вывод для слайсов и карт через JSON
	switch v.Kind() {
	case reflect.Slice, reflect.Map:
		// MarshalIndent для красивого вывода с отступами
		bytes, err := json.MarshalIndent(val, "", "  ")
		if err != nil {
			return fmt.Sprintf("Ошибка форматирования: %v", err)
		}
		return string(bytes)
	}

	// Стандартный вывод для всего остального
	return fmt.Sprintf("%v", val)
}

// ... (функция containsSensitiveKeyword остается без изменений) ...
func containsSensitiveKeyword(key string) bool {
	sensitiveWords := []string{"credentials", "secret", "token", "password", "private_key"}
	for _, word := range sensitiveWords {
		if strings.Contains(strings.ToLower(key), word) {
			return true
		}
	}
	return false
}
