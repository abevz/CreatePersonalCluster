package tofu

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/abevz/createpersonalcluster/cpc-go/internal/config"
	"golang.org/x/crypto/ssh"
)

// UploadSnippets connects to a Proxmox node and uploads generated snippets using the private key from config.
func UploadSnippets(cfg *config.Deployment, workDir string) error {
	log.Println("   Preparing to upload snippets via SSH...")

	// --- 1. Get SSH Config from our main config ---
	sshUser := cfg.Spec.ProxmoxSSH.User
	targetBasePath := cfg.Spec.ProxmoxSSH.SnippetPath

	// Extract host from proxmox endpoint URL
	proxmoxURL := cfg.Spec.ProviderConfig["proxmox"].(map[string]interface{})["endpoint"].(string)
	sshHost := strings.Split(strings.Split(proxmoxURL, "//")[1], ":")[0]
	sshPort := "22"

	// --- 2. Parse the private key from the config ---
	privateKey := cfg.PostInstallSecrets.VMSSH_PrivateKey
	signer, err := ssh.ParsePrivateKey([]byte(privateKey))
	if err != nil {
		return fmt.Errorf("unable to parse private key: %w", err)
	}

	// --- 3. Configure SSH Client ---
	sshConfig := &ssh.ClientConfig{
		User: sshUser,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signer),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // WARNING: Insecure, for lab environment only
	}

	// --- 4. Connect to SSH Server ---
	client, err := ssh.Dial("tcp", sshHost+":"+sshPort, sshConfig)
	if err != nil {
		return fmt.Errorf("failed to dial SSH server: %w", err)
	}
	defer client.Close()

	log.Printf("   Successfully connected to %s via SSH as user %s", sshHost, sshUser)

	// --- 5. Walk through local snippets and upload each file ---
	localSnippetsDir := filepath.Join(workDir, "snippets")

	return filepath.Walk(localSnippetsDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil // Skip directories
		}

		// Create a new session for each command
		session, err := client.NewSession()
		if err != nil {
			return fmt.Errorf("failed to create SSH session: %w", err)
		}
		defer session.Close()

		localFile, err := os.Open(path)
		if err != nil {
			return fmt.Errorf("failed to open local snippet %s: %w", path, err)
		}
		defer localFile.Close()

		remotePath := filepath.Join(targetBasePath, info.Name())

		// Get stdin pipe for the remote command
		stdin, err := session.StdinPipe()
		if err != nil {
			return err
		}

		// Start remote command `cat > /remote/path`
		go func() {
			defer stdin.Close()
			_, copyErr := io.Copy(stdin, localFile)
			if copyErr != nil {
				log.Printf("ERROR: failed to stream file content: %v", copyErr)
			}
		}()

		// Run the remote command and capture output
		output, err := session.CombinedOutput(fmt.Sprintf("cat > %s", remotePath))
		if err != nil {
			return fmt.Errorf("remote command failed for %s: %w. Output: %s", remotePath, err, string(output))
		}

		log.Printf("   Uploaded snippet %s to %s", info.Name(), remotePath)
		return nil
	})
}
