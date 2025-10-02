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

		// Используем глобальную переменную DeploymentsRoot, определенную в root.go
		deploymentPath := filepath.Join(DeploymentsRoot, "deployments", deploymentName)

		log.Printf("Загрузка конфигурации из: %s", deploymentPath)

		if _, err := os.Stat(deploymentPath); os.IsNotExist(err) {
			log.Fatalf("Ошибка: директория развертывания '%s' не найдена.", deploymentPath)
		}

		// Загружаем конфигурацию с помощью нашего модуля
		cfg, err := config.Load(deploymentPath)
		if err != nil {
			log.Fatalf("Ошибка: не удалось загрузить конфигурацию: %v", err)
		}

		// Шаг 2: Объявляем переменную, КУДА будем загружать данные.
		// Убедись, что тип `config.Deployment` доступен.
		var deploymentData config.Deployment

		// Шаг 3: ЭТОТ ШАГ БЫЛ ПРОПУЩЕН.
		// "Перекладываем" данные из объекта `k` в нашу структуру `deploymentData`.
		if err := k.Unmarshal("", &deploymentData); err != nil {
			log.Fatalf("Ошибка парсинга конфигурации в структуру: %v", err)
		}

		// Твоя отладочная печать теперь покажет чистую структуру.
		log.Printf("DEBUG: Загруженная структура: %+v\n", deploymentData)

		log.Printf("DEBUG: Загруженная структура: %+v\n", cfg)

		// --- Логика вывода в таблицу ---
		t := table.NewWriter()
		t.SetOutputMirror(os.Stdout)
		t.SetStyle(table.StyleRounded)
		t.SetTitle("Объединенная Конфигурация для '%s'", deploymentName)
		t.AppendHeader(table.Row{"Ключ Конфигурации", "Значение"})

		// Рекурсивно обходим структуру конфигурации и добавляем строки в таблицу
		appendStructToTable(t, reflect.ValueOf(*cfg), "")

		t.Render()
	},
}

// appendStructToTable - это рекурсивная функция, которая "разворачивает"
// вложенную структуру в плоский список ключ-значение для таблицы.
func appendStructToTable(t table.Writer, val reflect.Value, prefix string) {
	// Убеждаемся, что работаем со структурой, а не с указателем на нее
	if val.Kind() == reflect.Ptr {
		val = val.Elem()
	}

	// Если это не структура, завершаем рекурсию
	if val.Kind() != reflect.Struct {
		return
	}

	// Проходим по всем полям структуры
	for i := 0; i < val.NumField(); i++ {
		field := val.Field(i)
		fieldType := val.Type().Field(i)

		// Используем тег `mapstructure` как имя ключа в YAML
		keyName := fieldType.Tag.Get("mapstructure")
		if keyName == "" {
			continue // Пропускаем поля без тега
		}

		// Формируем полный ключ (например, spec.provider)
		fullKey := keyName
		if prefix != "" {
			fullKey = prefix + "." + keyName
		}

		// В зависимости от типа поля, решаем, что делать дальше
		switch field.Kind() {
		case reflect.Struct:
			// Если поле - это вложенная структура, уходим в рекурсию
			appendStructToTable(t, field, fullKey)
		case reflect.Map:
			// Если поле - это карта (map), итерируемся по ее ключам
			for _, key := range field.MapKeys() {
				mapValue := field.MapIndex(key)
				rowKey := fullKey + "." + fmt.Sprintf("%v", key.Interface())
				t.AppendRow(table.Row{rowKey, formatValue(rowKey, mapValue)})
			}
		default:
			// Для простых типов (string, int, bool) просто добавляем строку
			t.AppendRow(table.Row{fullKey, formatValue(fullKey, field)})
		}
	}
}

// formatValue форматирует значение для вывода и скрывает секреты.
func formatValue(key string, v reflect.Value) string {
	// Простое правило: если ключ содержит слово "credentials" или "secret", скрываем значение.
	// В будущем можно сделать эту логику умнее.
	if containsSensitiveKeyword(key) {
		return "*** SENSITIVE ***"
	}

	// Для указателей получаем реальное значение
	if v.Kind() == reflect.Ptr && !v.IsNil() {
		v = v.Elem()
	}

	return fmt.Sprintf("%v", v.Interface())
}

// containsSensitiveKeyword проверяет, содержит ли ключ "секретные" слова.
func containsSensitiveKeyword(key string) bool {
	sensitiveWords := []string{"credentials", "secret", "token", "password", "private_key"}
	for _, word := range sensitiveWords {
		if strings.Contains(key, word) {
			return true
		}
	}
	return false
}

func init() {
	deploymentCmd.AddCommand(configCmd)
}
