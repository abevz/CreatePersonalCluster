// File: internal/view/table.go
package view

import (
	"os"
	"sort"
	"strings"

	"github.com/jedib0t/go-pretty/v6/table"
	"github.com/knadh/koanf/v2"
)

func RenderConfig(k *koanf.Koanf) {
	t := table.NewWriter()
	t.SetOutputMirror(os.Stdout)
	t.AppendHeader(table.Row{"Key", "Value"})

	keys := k.Keys()
	sort.Strings(keys)

	for _, key := range keys {
		// Простая эвристика для определения секрета
		isSecret := strings.Contains(key, "secret") ||
			strings.Contains(key, "password") ||
			strings.Contains(key, "private_key") ||
			strings.Contains(key, "credentials")

		var value interface{}
		if isSecret {
			value = "*** SENSITIVE ***"
		} else {
			value = k.Get(key)
		}

		t.AppendRow(table.Row{key, value})
		t.AppendSeparator()
	}

	t.Render()
}
