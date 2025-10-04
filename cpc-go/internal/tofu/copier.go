// File: internal/tofu/copier.go
package tofu

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// CopyTfFiles intelligently copies only .tf files, preserving the directory structure
// and skipping unnecessary directories like .terraform.
func CopyTfFiles(srcDir, destDir string) error {
	// A set of directories to completely ignore
	ignoreDirs := map[string]bool{
		".terraform": true,
	}

	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Get the relative path to preserve the structure
		relPath, err := filepath.Rel(srcDir, path)
		if err != nil {
			return err
		}
		if relPath == "." {
			return nil // Skip the root itself
		}

		// If the directory is in our ignore list, skip it and everything inside it
		if info.IsDir() && ignoreDirs[info.Name()] {
			return filepath.SkipDir
		}

		destPath := filepath.Join(destDir, relPath)

		if info.IsDir() {
			// Create corresponding directory in the destination
			return os.MkdirAll(destPath, info.Mode())
		}

		// Copy only files with a .tf extension
		if strings.HasSuffix(info.Name(), ".tf") {
			srcFile, err := os.Open(path)
			if err != nil {
				return fmt.Errorf("failed to open source file %s: %w", path, err)
			}
			defer srcFile.Close()

			destFile, err := os.Create(destPath)
			if err != nil {
				return fmt.Errorf("failed to create destination file %s: %w", destPath, err)
			}
			defer destFile.Close()

			_, err = io.Copy(destFile, srcFile)
			if err != nil {
				return fmt.Errorf("failed to copy file content to %s: %w", destPath, err)
			}
		}

		return nil
	})
}
