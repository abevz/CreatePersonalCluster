# AWS Provider Implementation for CPC Multi-Cloud

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables specific to AWS implementation
variable "aws_config" {
  description = "AWS-specific configuration"
  type = object({
    region             = string
    availability_zones = optional(list(string), [])
    
    # VPC Configuration
    vpc_cidr           = optional(string, "10.0.0.0/16")
    enable_dns_support = optional(bool, true)
    enable_dns_hostnames = optional(bool, true)
    
    # Instance Configuration
    key_pair_name      = string
    instance_profile   = optional(string)
    
    # Security
    enable_flow_logs   = optional(bool, false)
    allowed_cidr_blocks = optional(list(string), ["0.0.0.0/0"])
  })
}

# Get available AZs if not specified
data "aws_availability_zones" "available" {
  state = "available"
}

# Instance type mapping based on node role and requirements
locals {
  # Default instance types for different node roles
  default_instance_types = {
    control_plane = {
      small  = "t3.medium"   # 2 vCPU, 4 GiB RAM
      medium = "t3.large"    # 2 vCPU, 8 GiB RAM  
      large  = "m5.large"    # 2 vCPU, 8 GiB RAM
    }
    worker = {
      small  = "t3.small"    # 2 vCPU, 2 GiB RAM
      medium = "t3.medium"   # 2 vCPU, 4 GiB RAM
      large  = "t3.large"    # 2 vCPU, 8 GiB RAM
    }
  }
  
  # Use specified AZs or auto-select first 3 available
  availability_zones = length(var.aws_config.availability_zones) > 0 ? 
    var.aws_config.availability_zones : 
    slice(data.aws_availability_zones.available.names, 0, min(3, length(data.aws_availability_zones.available.names)))
    
  # Common tags for all resources
  common_tags = {
    Project     = "CPC-Kubernetes"
    Environment = var.cluster_config.name
    ManagedBy   = "Terraform"
    Provider    = "AWS"
  }
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = var.aws_config.vpc_cidr
  enable_dns_support   = var.aws_config.enable_dns_support
  enable_dns_hostnames = var.aws_config.enable_dns_hostnames
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-igw"
  })
}

# Public Subnets (for control plane if public access enabled)
resource "aws_subnet" "public" {
  count = length(local.availability_zones)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.aws_config.vpc_cidr, 8, count.index)
  availability_zone = local.availability_zones[count.index]
  
  map_public_ip_on_launch = var.cluster_config.networking.public_access
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-public-${count.index + 1}"
    Type = "Public"
  })
}

# Private Subnets (for worker nodes)
resource "aws_subnet" "private" {
  count = length(local.availability_zones)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.aws_config.vpc_cidr, 8, count.index + 10)
  availability_zone = local.availability_zones[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-private-${count.index + 1}"
    Type = "Private"
  })
}

# NAT Gateways for private subnets (if private nodes need internet)
resource "aws_eip" "nat" {
  count = var.cluster_config.networking.public_access ? length(local.availability_zones) : 0
  
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-nat-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "main" {
  count = var.cluster_config.networking.public_access ? length(local.availability_zones) : 0
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-nat-${count.index + 1}"
  })
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-public-rt"
  })
}

resource "aws_route_table" "private" {
  count = length(local.availability_zones)
  
  vpc_id = aws_vpc.main.id
  
  dynamic "route" {
    for_each = var.cluster_config.networking.public_access ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[count.index].id
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-private-rt-${count.index + 1}"
  })
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups
resource "aws_security_group" "control_plane" {
  name_prefix = "${var.cluster_config.name}-cp-"
  vpc_id      = aws_vpc.main.id
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.aws_config.allowed_cidr_blocks
  }
  
  # Kubernetes API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.aws_config.allowed_cidr_blocks
  }
  
  # etcd
  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
  }
  
  # Kubelet API
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    self      = true
  }
  
  # Control plane to workers communication
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }
  
  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-control-plane-sg"
  })
}

resource "aws_security_group" "worker" {
  name_prefix = "${var.cluster_config.name}-worker-"
  vpc_id      = aws_vpc.main.id
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.aws_config.allowed_cidr_blocks
  }
  
  # Kubelet API
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    self      = true
  }
  
  # NodePort services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.aws_config.allowed_cidr_blocks
  }
  
  # Control plane to workers communication
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }
  
  # Worker to worker communication (CNI)
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }
  
  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-worker-sg"
  })
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  count = var.os_config.family == "ubuntu" ? 1 : 0
  
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*${var.os_config.version}*-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get latest Amazon Linux AMI
data "aws_ami" "amazonlinux" {
  count = var.os_config.family == "amazonlinux" ? 1 : 0
  
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# User data for cloud-init
locals {
  cloud_init_user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    ssh_public_key = file(var.ssh_public_key_path)
    hostname_prefix = var.cluster_config.name
  }))
  
  # Select appropriate AMI
  ami_id = (
    var.os_config.custom_image_id != null ? var.os_config.custom_image_id :
    var.os_config.family == "ubuntu" ? data.aws_ami.ubuntu[0].id :
    var.os_config.family == "amazonlinux" ? data.aws_ami.amazonlinux[0].id :
    null
  )
}

# Control Plane Instances
resource "aws_instance" "control_plane" {
  count = var.cluster_config.control_plane.count
  
  ami           = local.ami_id
  instance_type = var.cluster_config.control_plane.instance_type
  key_name      = var.aws_config.key_pair_name
  
  subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids = [aws_security_group.control_plane.id]
  
  iam_instance_profile = var.aws_config.instance_profile
  
  user_data = local.cloud_init_user_data
  
  root_block_device {
    volume_type = var.cluster_config.control_plane.disk_type
    volume_size = var.cluster_config.control_plane.disk_size
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${var.cluster_config.name}-cp-${count.index + 1}-root"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-cp-${count.index + 1}"
    Role = "control-plane"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Worker Instances
resource "aws_instance" "worker" {
  count = var.cluster_config.workers.count
  
  ami           = local.ami_id
  instance_type = var.cluster_config.workers.instance_type
  key_name      = var.aws_config.key_pair_name
  
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.worker.id]
  
  iam_instance_profile = var.aws_config.instance_profile
  
  user_data = local.cloud_init_user_data
  
  root_block_device {
    volume_type = var.cluster_config.workers.disk_type
    volume_size = var.cluster_config.workers.disk_size
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${var.cluster_config.name}-worker-${count.index + 1}-root"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-worker-${count.index + 1}"
    Role = "worker"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer for API Server (optional)
resource "aws_lb" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  
  name               = "${var.cluster_config.name}-api"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.control_plane.id]
  subnets            = aws_subnet.public[*].id
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-api-lb"
  })
}

resource "aws_lb_target_group" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  
  name     = "${var.cluster_config.name}-api"
  port     = 6443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/readyz"
    matcher             = "200"
    port                = "6443"
    protocol            = "HTTPS"
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_config.name}-api-tg"
  })
}

resource "aws_lb_listener" "api_server" {
  count = var.cluster_config.networking.public_access ? 1 : 0
  
  load_balancer_arn = aws_lb.api_server[0].arn
  port              = "6443"
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn # Would need to be provided
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server[0].arn
  }
}

resource "aws_lb_target_group_attachment" "api_server" {
  count = var.cluster_config.networking.public_access ? var.cluster_config.control_plane.count : 0
  
  target_group_arn = aws_lb_target_group.api_server[0].arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

# Local values for outputs
locals {
  control_plane_nodes = [
    for i, instance in aws_instance.control_plane : {
      name        = instance.tags.Name
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      hostname    = "${var.cluster_config.name}-cp-${i + 1}"
      instance_id = instance.id
    }
  ]
  
  worker_nodes = [
    for i, instance in aws_instance.worker : {
      name        = instance.tags.Name
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      hostname    = "${var.cluster_config.name}-worker-${i + 1}"
      instance_id = instance.id
    }
  ]
  
  ssh_user = var.os_config.family == "ubuntu" ? "ubuntu" : "ec2-user"
  
  vpc_id = aws_vpc.main.id
  subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
  security_group_ids = [aws_security_group.control_plane.id, aws_security_group.worker.id]
  load_balancer_dns = var.cluster_config.networking.public_access ? aws_lb.api_server[0].dns_name : null
}
