package config

// Deployment - это корневая структура, которая представляет
// объединенную конфигурацию из deployment.yaml и secrets.sops.yaml.
type Deployment struct {
	APIVersion  string      `mapstructure:"apiVersion"`
	Kind        string      `mapstructure:"kind"`
	Metadata    Metadata    `mapstructure:"metadata"`
	TofuBackend TofuBackend `mapstructure:"tofuBackend"`
	Spec        Spec        `mapstructure:"spec"`

	// Эти поля будут загружены из secrets.sops.yaml
	ProviderCredentials  ProviderCredentials  `mapstructure:"provider_credentials"`
	S3BackendCredentials S3BackendCredentials `mapstructure:"s3_backend_credentials"`
	PostInstallSecrets   PostInstallSecrets   `mapstructure:"post_install_secrets"`
}

// Metadata содержит мета-информацию о развертывании.
type Metadata struct {
	Name string `mapstructure:"name"`
}

// TofuBackend описывает конфигурацию бэкенда для OpenTofu.
type TofuBackend struct {
	Type   string            `mapstructure:"type"`
	Config map[string]string `mapstructure:"config"`
}

// Spec описывает желаемое состояние инфраструктуры.
type Spec struct {
	Provider         string             `mapstructure:"provider"`
	ProviderConfig   ProviderConfigSpec `mapstructure:"provider_config"`
	InstanceProfiles []InstanceProfile  `mapstructure:"instanceProfiles"`
	NodeGroups       []NodeGroup        `mapstructure:"nodeGroups"`
}

// ProviderConfigSpec содержит не-секретные настройки для провайдеров.
type ProviderConfigSpec struct {
	Proxmox map[string]string `mapstructure:"proxmox"`
	AWS     map[string]string `mapstructure:"aws"`
}

// InstanceProfile определяет шаблон/тип виртуальной машины.
type InstanceProfile struct {
	Name             string           `mapstructure:"name"`
	Resources        Resources        `mapstructure:"resources"`
	ProviderSettings ProviderSettings `mapstructure:"providerSettings"`
}

// Resources описывает общие параметры ВМ (CPU, память, диск).
type Resources struct {
	CPU    int    `mapstructure:"cpu"`
	Memory string `mapstructure:"memory"`
	Disk   struct {
		Size string `mapstructure:"size"`
	} `mapstructure:"disk"`
}

// ProviderSettings содержит специфичные для провайдера параметры ВМ.
type ProviderSettings struct {
	Proxmox map[string]string `mapstructure:"proxmox"`
	AWS     map[string]string `mapstructure:"aws"`
}

// NodeGroup описывает группу однотипных нод.
type NodeGroup struct {
	Name    string `mapstructure:"name"`
	Profile string `mapstructure:"profile"`
	Count   int    `mapstructure:"count"`
}

// --- Структуры для секретов ---

// ProviderCredentials содержит секретные учетные данные для Tofu-провайдеров.
type ProviderCredentials struct {
	Proxmox map[string]string `mapstructure:"proxmox"`
	AWS     map[string]string `mapstructure:"aws"`
}

// S3BackendCredentials содержит секреты для S3 бэкенда.
type S3BackendCredentials struct {
	AccessKey string `mapstructure:"access_key"`
	SecretKey string `mapstructure:"secret_key"`
}

// PostInstallSecrets содержит секреты для Ansible.
type PostInstallSecrets struct {
	VMSSH_PrivateKey string `mapstructure:"vm_ssh_private_key"`
}
