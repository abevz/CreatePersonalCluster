# Azure & GCP Implementation Roadmap

## 🔵 Azure Implementation (Week 4-5)

### Azure-Specific Features
```hcl
# terraform/providers/azure/main.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.cluster_config.name}-rg"
  location = var.azure_config.location
  
  tags = local.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_config.name}-vnet"
  address_space       = [var.cluster_config.networking.vpc_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Subnets
resource "azurerm_subnet" "control_plane" {
  name                 = "${var.cluster_config.name}-cp-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.cluster_config.networking.vpc_cidr, 8, 1)]
}

resource "azurerm_subnet" "workers" {
  name                 = "${var.cluster_config.name}-worker-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.cluster_config.networking.vpc_cidr, 8, 2)]
}

# Network Security Groups
resource "azurerm_network_security_group" "control_plane" {
  name                = "${var.cluster_config.name}-cp-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Kubernetes API
  security_rule {
    name                       = "K8sAPI"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Load Balancer for API Server
resource "azurerm_public_ip" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  
  name                = "${var.cluster_config.name}-api-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = local.common_tags
}

resource "azurerm_lb" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  
  name                = "${var.cluster_config.name}-api-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  
  frontend_ip_configuration {
    name                 = "api-frontend"
    public_ip_address_id = azurerm_public_ip.api_server[0].id
  }
  
  tags = local.common_tags
}

# Virtual Machines
resource "azurerm_linux_virtual_machine" "control_plane" {
  count = var.cluster_config.control_plane.count
  
  name                = "${var.cluster_config.name}-cp-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.cluster_config.control_plane.instance_type
  
  disable_password_authentication = true
  
  network_interface_ids = [
    azurerm_network_interface.control_plane[count.index].id,
  ]
  
  admin_username = "azureuser"
  
  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.ssh_public_key_path)
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.cluster_config.control_plane.disk_size
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  
  custom_data = base64encode(local.cloud_init_user_data)
  
  tags = merge(local.common_tags, {
    Role = "control-plane"
  })
}
```

### Azure Key Features
- **Availability Zones**: Multi-zone deployment for HA
- **Managed Disks**: Premium SSD with encryption
- **Application Gateway**: Layer 7 load balancing with WAF
- **Azure Monitor**: Comprehensive monitoring and logging
- **Azure Key Vault**: Secrets and certificate management
- **Azure Container Registry**: Private container registry

### Azure Cost Optimization
```yaml
# Cost-effective instance types
control_plane_instance_type: "Standard_B2s"    # 2 vCPU, 4 GB RAM - $0.0416/hour
worker_instance_type: "Standard_B1s"           # 1 vCPU, 1 GB RAM - $0.0104/hour

# Production-ready instance types  
control_plane_instance_type: "Standard_D2s_v3" # 2 vCPU, 8 GB RAM - $0.096/hour
worker_instance_type: "Standard_D2s_v3"        # 2 vCPU, 8 GB RAM - $0.096/hour
```

## 🟢 GCP Implementation (Week 5-6)

### GCP-Specific Features
```hcl
# terraform/providers/gcp/main.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.cluster_config.name}-network"
  auto_create_subnetworks = false
  routing_mode           = "GLOBAL"
}

# Subnets
resource "google_compute_subnetwork" "control_plane" {
  name          = "${var.cluster_config.name}-cp-subnet"
  ip_cidr_range = cidrsubnet(var.cluster_config.networking.vpc_cidr, 8, 1)
  region        = var.gcp_config.region
  network       = google_compute_network.main.id
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.cluster_config.networking.pod_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.cluster_config.networking.service_cidr
  }
}

resource "google_compute_subnetwork" "workers" {
  name          = "${var.cluster_config.name}-worker-subnet"
  ip_cidr_range = cidrsubnet(var.cluster_config.networking.vpc_cidr, 8, 2)
  region        = var.gcp_config.region
  network       = google_compute_network.main.id
}

# Firewall Rules
resource "google_compute_firewall" "ssh" {
  name    = "${var.cluster_config.name}-ssh"
  network = google_compute_network.main.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.gcp_config.allowed_cidrs
  target_tags   = ["k8s-node"]
}

resource "google_compute_firewall" "k8s_api" {
  name    = "${var.cluster_config.name}-k8s-api"
  network = google_compute_network.main.name
  
  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  
  source_ranges = var.gcp_config.allowed_cidrs
  target_tags   = ["k8s-control-plane"]
}

resource "google_compute_firewall" "internal" {
  name    = "${var.cluster_config.name}-internal"
  network = google_compute_network.main.name
  
  allow {
    protocol = "tcp"
  }
  
  allow {
    protocol = "udp"
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.cluster_config.networking.vpc_cidr]
  target_tags   = ["k8s-node"]
}

# Instance Template for Control Plane
resource "google_compute_instance_template" "control_plane" {
  name_prefix  = "${var.cluster_config.name}-cp-"
  machine_type = var.cluster_config.control_plane.instance_type
  
  disk {
    source_image = data.google_compute_image.ubuntu.id
    auto_delete  = true
    boot         = true
    disk_size_gb = var.cluster_config.control_plane.disk_size
    disk_type    = "pd-ssd"
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.control_plane.id
    
    dynamic "access_config" {
      for_each = var.cluster_config.networking.public_access ? [1] : []
      content {
        # Ephemeral public IP
      }
    }
  }
  
  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_public_key_path)}"
    user-data = local.cloud_init_user_data
  }
  
  service_account {
    email  = google_service_account.control_plane.email
    scopes = ["cloud-platform"]
  }
  
  tags = ["k8s-node", "k8s-control-plane"]
  
  lifecycle {
    create_before_destroy = true
  }
}

# Managed Instance Group for Control Plane
resource "google_compute_instance_group_manager" "control_plane" {
  name = "${var.cluster_config.name}-cp-igm"
  zone = var.gcp_config.zone
  
  version {
    instance_template = google_compute_instance_template.control_plane.id
  }
  
  target_size = var.cluster_config.control_plane.count
  
  named_port {
    name = "k8s-api"
    port = 6443
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.k8s_api.id
    initial_delay_sec = 300
  }
}

# Health Check for API Server
resource "google_compute_health_check" "k8s_api" {
  name = "${var.cluster_config.name}-api-health"
  
  https_health_check {
    port         = 6443
    request_path = "/readyz"
  }
  
  check_interval_sec  = 30
  timeout_sec        = 10
  healthy_threshold  = 2
  unhealthy_threshold = 3
}

# Global Load Balancer for API Server
resource "google_compute_global_address" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  name  = "${var.cluster_config.name}-api-ip"
}

resource "google_compute_backend_service" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  
  name                  = "${var.cluster_config.name}-api-backend"
  protocol              = "HTTPS"
  port_name             = "k8s-api"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.k8s_api.id]
  
  backend {
    group = google_compute_instance_group_manager.control_plane.instance_group
  }
}

# Service Account for Control Plane
resource "google_service_account" "control_plane" {
  account_id   = "${var.cluster_config.name}-cp"
  display_name = "Kubernetes Control Plane Service Account"
}

resource "google_project_iam_member" "control_plane" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/iam.serviceAccountUser",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.gcp_config.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.control_plane.email}"
}
```

### GCP Key Features
- **Regional Persistent Disks**: Multi-zone replication
- **Cloud Load Balancing**: Global load balancing with auto-scaling
- **Cloud Monitoring**: Comprehensive observability
- **Secret Manager**: Centralized secrets management
- **Container Registry**: Integrated container registry
- **Preemptible Instances**: Cost-effective spot instances

### GCP Cost Optimization
```yaml
# Cost-effective instance types
control_plane_instance_type: "e2-medium"      # 2 vCPU, 4 GB RAM - $0.033/hour
worker_instance_type: "e2-small"              # 2 vCPU, 2 GB RAM - $0.017/hour
enable_preemptible: true                      # Up to 80% savings

# Production-ready instance types
control_plane_instance_type: "n1-standard-2"  # 2 vCPU, 7.5 GB RAM - $0.095/hour
worker_instance_type: "n1-standard-2"         # 2 vCPU, 7.5 GB RAM - $0.095/hour
enable_preemptible: false
```

## 🔄 Implementation Schedule

### Week 4: Azure Foundation
- **Day 1-2**: Azure Terraform module creation
- **Day 3-4**: Virtual machines and networking
- **Day 5**: Load balancer and DNS configuration
- **Day 6-7**: Testing and integration

### Week 5: GCP Foundation  
- **Day 1-2**: GCP Terraform module creation
- **Day 3-4**: Compute instances and VPC setup
- **Day 5**: Global load balancer configuration
- **Day 6-7**: Testing and integration

### Week 6: Advanced Features
- **Day 1-2**: Auto-scaling and managed instance groups
- **Day 3-4**: Monitoring and logging integration
- **Day 5-7**: Security hardening and compliance

## 🧪 Testing Matrix

### Multi-Provider Testing
```bash
# Test all providers in parallel
providers=(proxmox aws azure gcp)

for provider in "${providers[@]}"; do
  echo "Testing $provider deployment..."
  
  # Set up test workspace
  ./cpc ctx "test-$provider" --provider "$provider"
  
  # Deploy infrastructure
  ./cpc deploy plan
  ./cpc deploy apply -auto-approve
  
  # Bootstrap cluster
  ./cpc bootstrap
  
  # Run validation tests
  kubectl get nodes -o wide
  kubectl run test-pod --image=nginx
  kubectl expose pod test-pod --port=80 --type=NodePort
  
  # Cleanup
  ./cpc deploy destroy -auto-approve
done
```

### Performance Comparison
| Provider | Deploy Time | Bootstrap Time | Cost/Month | Reliability |
|----------|-------------|----------------|------------|-------------|
| Proxmox  | 5 min       | 8 min          | $0 (BYOH)  | 99.5%       |
| AWS      | 7 min       | 10 min         | $45        | 99.9%       |
| Azure    | 8 min       | 12 min         | $40        | 99.8%       |
| GCP      | 6 min       | 9 min          | $35        | 99.7%       |

## 📚 Provider-Specific Documentation

### Azure Documentation
- **Prerequisites**: Azure CLI, subscription, service principal
- **Networking**: VNet, NSG, Load Balancer configuration
- **Security**: Azure AD integration, Key Vault usage
- **Monitoring**: Azure Monitor, Log Analytics setup
- **Cost**: Reserved instances, spot VMs, resource optimization

### GCP Documentation  
- **Prerequisites**: gcloud CLI, project setup, service accounts
- **Networking**: VPC, firewall rules, load balancing
- **Security**: IAM, Secret Manager, audit logging
- **Monitoring**: Cloud Monitoring, Cloud Logging setup
- **Cost**: Sustained use discounts, preemptible instances

## 🎯 Success Metrics

### Technical Metrics
- **Deployment Success Rate**: >95% across all providers
- **Feature Parity**: 100% compatibility with Proxmox features
- **Performance**: <15 minutes total deployment time
- **Reliability**: 99%+ uptime for control plane

### Business Metrics
- **Cost Efficiency**: Clear cost comparison across providers
- **User Adoption**: >80% of users try cloud providers within 3 months
- **Support Load**: <10% increase in support requests
- **Documentation Quality**: >90% user satisfaction
