// Package templates contains the string templates for generating example
// deployment configurations.
package templates

// ProxmoxDeployment is the template for a Proxmox deployment.yaml.
const ProxmoxDeployment = `
apiVersion: cpc.abevz.dev/v1alpha1
kind: ClusterDeployment
metadata:
  name: proxmox-k8s-example

tofuBackend:
  type: local # For simplicity, can be changed to s3
  config:
    path: "terraform.tfstate"

spec:
  provider: proxmox
  provider_config:
    proxmox:
      node: "pve" # Specify your Proxmox node name
      endpoint: "https://<your-proxmox-ip>:8006"

  instanceProfiles:
    - name: "k8s-node"
      resources:
        cpu: 2
        memory: "4Gi"
        disk: { size: "50Gi" }
      providerSettings:
        proxmox:
          template: "ubuntu-2204-cloud" # The name of your cloud-init template

  nodeGroups:
    - name: "control-plane"
      profile: "k8s-node"
      count: 1
    - name: "workers"
      profile: "k8s-node"
      count: 2
`

// ProxmoxSecrets is the template for a Proxmox secrets.sops.yaml.
const ProxmoxSecrets = `
provider_credentials:
  proxmox:
    token_id: "user@pve!token-name"
    token_secret: "your-proxmox-api-token-secret"

post_install_secrets:
  vm_ssh_private_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
`
