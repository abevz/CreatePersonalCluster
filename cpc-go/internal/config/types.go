package config

type ProxmoxSSH struct {
	User        string `koanf:"user"`
	SnippetPath string `koanf:"snippetPath"`
}

type VMCredentials struct {
	Username string `koanf:"username"`
	Password string `koanf:"password"`
}

type PostInstallSecrets struct {
	VMCredentials    VMCredentials `koanf:"vm_credentials"`
	VMSSH_PrivateKey string        `koanf:"vm_ssh_private_key"`
	// NEW: Add the public key field
	VMSSH_PublicKey string `koanf:"vm_ssh_public_key"`
	// Use map for other dynamic secrets like cloudflare, harbor, etc.
	OtherSecrets map[string]interface{} `koanf:",remain"`
}

// Deployment - это корневая структура всей конфигурации.
// Теги `koanf:"..."` сопоставляют поля с ключами в YAML.
type Deployment struct {
	APIVersion           string               `koanf:"apiVersion"`
	Kind                 string               `koanf:"kind"`
	Metadata             Metadata             `koanf:"metadata"`
	TofuBackend          TofuBackend          `koanf:"tofuBackend"`
	Spec                 Spec                 `koanf:"spec"`
	ProviderCredentials  ProviderCredentials  `koanf:"provider_credentials"`
	S3BackendCredentials S3BackendCredentials `koanf:"s3_backend_credentials"`
	PostInstallSecrets   PostInstallSecrets   `koanf:"post_install_secrets"`
}

type Metadata struct {
	Name string `koanf:"name"`
}

type TofuBackend struct {
	Type   string                 `koanf:"type"`
	Config map[string]interface{} `koanf:"config"`
}

type Spec struct {
	Provider          string                   `koanf:"provider"`
	ProviderConfig    map[string]interface{}   `koanf:"provider_config"`
	PostCreateTasks   []map[string]interface{} `koanf:"postCreateTasks"`
	ClusterDomain     string                   `koanf:"clusterDomain"`
	NodeGroups        []NodeGroup              `koanf:"nodeGroups"`
	TfvarsSchema      string                   `koanf:"tfvarsSchema"`
	Variables         map[string]interface{}   `koanf:"variables"`
	CloudInitTemplate string                   `koanf:"cloudInitTemplate"`
	ProxmoxSSH        ProxmoxSSH               `koanf:"proxmoxSSH"`
}

// NEW: Add this whole new struct
type NodeGroup struct {
	Name       string `koanf:"name"`
	RolePrefix string `koanf:"rolePrefix"`
	Profile    string `koanf:"profile"`
	Count      int    `koanf:"count"`
}

type ProviderCredentials struct {
	Proxmox map[string]string `koanf:"proxmox"`
	// Здесь могут быть и другие провайдеры, например AWS
}

type S3BackendCredentials struct {
	AccessKey string `koanf:"access_key"`
	SecretKey string `koanf:"secret_key"`
}
