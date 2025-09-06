# AWS Provider Implementation Checklist

## 🎯 Week 1: AWS Foundation

### Day 1-2: Terraform AWS Module
- [x] Create `terraform/providers/aws/` directory structure
- [x] Implement VPC and networking components
- [x] Create security groups for K8s cluster
- [x] Add EC2 instance resources for control plane and workers
- [ ] Test basic infrastructure deployment

### Day 3-4: Instance Configuration
- [ ] Create AMI data sources for Ubuntu/Amazon Linux
- [ ] Implement cloud-init user data templates
- [ ] Add EBS volume encryption
- [ ] Configure instance metadata service v2
- [ ] Test VM creation and SSH access

### Day 5-7: Load Balancer & DNS
- [ ] Add Application Load Balancer for API server
- [ ] Configure target groups and health checks
- [ ] Implement Route53 hosted zone (optional)
- [ ] Add SSL certificate management
- [ ] Test high availability setup

## 🔧 Week 2: AWS Integration

### Day 1-3: CPC CLI Integration
- [ ] Add AWS provider detection (`aws cli` check)
- [ ] Implement AWS credential validation
- [ ] Create AWS-specific context management
- [ ] Add AWS key pair creation/management
- [ ] Test provider switching

### Day 4-5: Terraform Integration
- [ ] Update tofu module for AWS provider
- [ ] Create AWS-specific variable files
- [ ] Implement AWS environment templates
- [ ] Test deployment commands

### Day 6-7: Ansible Compatibility
- [ ] Test existing Ansible playbooks with AWS instances
- [ ] Update inventory generation for AWS metadata
- [ ] Verify SSH connectivity and host key management
- [ ] Test complete bootstrap process

## 🚀 Week 3: AWS Advanced Features

### Day 1-2: Auto Scaling & Spot Instances
```hcl
# Auto Scaling Group for workers
resource "aws_autoscaling_group" "workers" {
  count = var.enable_autoscaling ? 1 : 0
  
  name                = "${var.cluster_config.name}-workers"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.workers[0].arn]
  
  min_size         = var.cluster_config.workers.min_count
  max_size         = var.cluster_config.workers.max_count
  desired_capacity = var.cluster_config.workers.count
  
  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }
  
  tag {
    key                 = "Name"
    value               = "${var.cluster_config.name}-worker"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_config.name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

# Spot instance support
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.cluster_config.name}-worker-"
  image_id      = local.ami_id
  instance_type = var.cluster_config.workers.instance_type
  key_name      = var.aws_config.key_pair_name
  
  vpc_security_group_ids = [aws_security_group.worker.id]
  
  # Spot instance configuration
  instance_market_options {
    market_type = var.enable_spot_instances ? "spot" : null
    
    dynamic "spot_options" {
      for_each = var.enable_spot_instances ? [1] : []
      content {
        max_price                      = var.spot_max_price
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }
  
  user_data = base64encode(local.cloud_init_user_data)
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type = var.cluster_config.workers.disk_type
      volume_size = var.cluster_config.workers.disk_size
      encrypted   = true
    }
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Role = "worker"
    })
  }
}
```

### Day 3-4: IAM Roles & Policies
```hcl
# IAM role for control plane
resource "aws_iam_role" "control_plane" {
  name = "${var.cluster_config.name}-control-plane"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Control plane policies
resource "aws_iam_role_policy" "control_plane" {
  name = "${var.cluster_config.name}-control-plane"
  role = aws_iam_role.control_plane.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeVpcs",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.cluster_config.name}-control-plane"
  role = aws_iam_role.control_plane.name
}

# Worker node IAM role
resource "aws_iam_role" "worker" {
  name = "${var.cluster_config.name}-worker"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_config.name}-worker"
  role = aws_iam_role.worker.name
}
```

### Day 5-7: Monitoring & Logging
- [ ] Add CloudWatch log groups for cluster logs
- [ ] Configure VPC Flow Logs
- [ ] Add CloudTrail for API logging
- [ ] Implement cost tagging strategy
- [ ] Create CloudWatch dashboards

## 📊 Testing Checklist

### Infrastructure Tests
- [ ] VPC and networking creation
- [ ] Security group rules validation
- [ ] EC2 instance creation and configuration
- [ ] Load balancer setup and health checks
- [ ] IAM roles and permissions

### Integration Tests
- [ ] CPC context switching to AWS
- [ ] Terraform deployment via CPC
- [ ] Ansible inventory generation
- [ ] SSH connectivity to instances
- [ ] Kubernetes bootstrap process

### End-to-End Tests
- [ ] Complete cluster deployment
- [ ] Pod networking functionality
- [ ] Service load balancing
- [ ] Persistent volume creation
- [ ] Cluster scaling operations

## 🔐 Security Configuration

### Network Security
```hcl
# Security group for control plane
resource "aws_security_group" "control_plane" {
  name_prefix = "${var.cluster_config.name}-cp-"
  vpc_id      = aws_vpc.main.id
  
  # Kubernetes API (6443) - restricted access
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.aws_config.api_allowed_cidrs
  }
  
  # SSH (22) - restricted access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.aws_config.ssh_allowed_cidrs
  }
  
  # etcd peer communication (2379-2380)
  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
  }
  
  # Kubelet API (10250)
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    cidr_blocks = [var.aws_config.vpc_cidr]
  }
  
  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### Instance Security
- [ ] Enable IMDSv2 (Instance Metadata Service v2)
- [ ] Disable root access
- [ ] Configure automatic security updates
- [ ] Enable EBS encryption by default
- [ ] Implement secrets management with AWS Systems Manager

## 💰 Cost Optimization

### Instance Sizing Recommendations
```yaml
# environments/aws/cost-optimized.tfvars
control_plane_instance_type = "t3.medium"    # $0.0416/hour
worker_instance_type        = "t3.small"     # $0.0208/hour
enable_spot_instances       = true
spot_max_price             = "0.01"          # 50% savings

# Standard configuration
control_plane_instance_type = "t3.large"     # $0.0832/hour  
worker_instance_type        = "t3.medium"    # $0.0416/hour
enable_spot_instances       = false
```

### Cost Monitoring
- [ ] Add AWS Cost and Usage Reports
- [ ] Implement budget alerts
- [ ] Tag all resources for cost tracking
- [ ] Create cost optimization recommendations

## 📚 Documentation

### User Guides
- [ ] AWS Prerequisites and Setup Guide
- [ ] AWS Deployment Guide
- [ ] AWS Troubleshooting Guide
- [ ] AWS Cost Optimization Guide

### Developer Guides  
- [ ] AWS Provider Architecture
- [ ] AWS Terraform Module Documentation
- [ ] AWS Testing Procedures
- [ ] AWS Security Best Practices

## 🎯 Success Criteria

### Functional Requirements
- [ ] Deploy 3-node cluster (1 CP, 2 workers) in under 10 minutes
- [ ] Support both Ubuntu 24.04 and Amazon Linux 2023
- [ ] Full compatibility with existing Ansible playbooks
- [ ] Automatic SSL certificate management
- [ ] High availability control plane option

### Non-Functional Requirements
- [ ] 99% deployment success rate
- [ ] Under $50/month for development cluster
- [ ] Complete documentation coverage
- [ ] Automated testing coverage >80%
- [ ] Zero breaking changes for existing users

## 🔄 Rollout Plan

### Phase 1: Beta Testing (Week 1)
- Internal testing with development workloads
- Basic functionality validation
- Security review and fixes

### Phase 2: Community Preview (Week 2)
- Limited community access
- Feedback collection and integration
- Documentation improvements

### Phase 3: General Availability (Week 3)
- Full feature rollout
- Production-ready documentation
- Support for production workloads
