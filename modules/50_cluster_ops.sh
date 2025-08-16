#!/bin/bash

# modules/50_cluster_ops.sh - Cluster Operations Module
# Part of CPC (Create Personal Cluster) - Modular Architecture
#
# This module provides cluster-level operational commands including addon management,
# cluster configuration, and maintenance operations.
# 
# Functions provided:
# - cpc_cluster_ops()             - Main entry point for cluster operations
# - cluster_upgrade_addons()      - Install/upgrade cluster addons with interactive menu
# - cluster_configure_coredns()   - Configure CoreDNS for local domain forwarding
# - cluster_show_upgrade_addons_help() - Display help for upgrade-addons command
# - cluster_show_configure_coredns_help() - Display help for configure-coredns command
#
# Dependencies:
# - lib/logging.sh for logging functions  
# - modules/00_core.sh for core utilities like get_repo_path, get_current_cluster_context
# - modules/20_ansible.sh for ansible_run_playbook function
# - Kubernetes cluster must be bootstrapped and accessible

#----------------------------------------------------------------------
# Cluster Operations Management Functions
#----------------------------------------------------------------------

# Main entry point for CPC cluster operations functionality
cpc_cluster_ops() {
    case "${1:-}" in
        upgrade-addons)
            shift
            if [[ "$1" == "-h" || "$1" == "--help" ]]; then
                cluster_show_upgrade_addons_help
                return 0
            fi
            cluster_upgrade_addons "$@"
            ;;
        configure-coredns)
            shift
            if [[ "$1" == "-h" || "$1" == "--help" ]]; then
                cluster_show_configure_coredns_help
                return 0
            fi
            cluster_configure_coredns "$@"
            ;;
        *)
            log_error "Unknown cluster operations command: ${1:-}"
            log_info "Available commands: upgrade-addons, configure-coredns"
            return 1
            ;;
    esac
}

# Install or upgrade cluster addons with interactive menu or direct specification
cluster_upgrade_addons() {
    # Parse command line arguments
    local addon_name=""
    local addon_version=""
    local force_addon=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --addon)
                force_addon="$2"
                shift 2
                ;;
            --version)
                addon_version="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # If no addon specified via --addon, show interactive menu
    if [ -z "$force_addon" ]; then
        echo -e "${BLUE}Select addon to install/upgrade:${ENDCOLOR}"
        echo ""
        echo "  1) all                                 - Install/upgrade all addons"
        echo "  2) calico                              - Calico CNI networking"
        echo "  3) metallb                             - MetalLB load balancer"
        echo "  4) metrics-server                      - Kubernetes Metrics Server" 
        echo "  5) coredns                             - CoreDNS DNS server"
        echo "  6) cert-manager                        - Certificate manager"
        echo "  7) kubelet-serving-cert-approver       - Kubelet cert approver"
        echo "  8) argocd                              - ArgoCD GitOps"
        echo "  9) ingress-nginx                       - NGINX Ingress Controller"
        echo ""
        read -r -p "Enter your choice [1-9]: " choice
        
        case $choice in
            1) addon_name="all" ;;
            2) addon_name="calico" ;;
            3) addon_name="metallb" ;;
            4) addon_name="metrics-server" ;;
            5) addon_name="coredns" ;;
            6) addon_name="cert-manager" ;;
            7) addon_name="kubelet-serving-cert-approver" ;;
            8) addon_name="argocd" ;;
            9) addon_name="ingress-nginx" ;;
            *) 
                log_error "Invalid choice: $choice"
                return 1
                ;;
        esac
    else
        addon_name="$force_addon"
    fi

    # Validate addon name
    case "$addon_name" in
        calico|metallb|metrics-server|coredns|cert-manager|kubelet-serving-cert-approver|argocd|ingress-nginx|all)
            ;;
        *)
            log_error "Invalid addon name: $addon_name"
            log_info "Valid options: calico, metallb, metrics-server, coredns, cert-manager, kubelet-serving-cert-approver, argocd, ingress-nginx, all"
            return 1
            ;;
    esac

    local extra_vars="-e addon_name=$addon_name"
    if [ -n "$addon_version" ]; then
        extra_vars="$extra_vars -e addon_version=$addon_version"
    fi

    log_step "Installing/upgrading cluster addon(s): $addon_name"
    ansible_run_playbook "pb_upgrade_addons_extended.yml" -l control_plane -e "addon_name=$addon_name" $([ -n "$addon_version" ] && echo "-e addon_version=$addon_version")
}

# Configure CoreDNS to forward local domain queries to Pi-hole DNS server
cluster_configure_coredns() {
    # Parse command line arguments
    local dns_server=""
    local domains=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dns-server)
                dns_server="$2"
                shift 2
                ;;
            --domains)
                domains="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Get DNS server from Terraform if not specified
    if [ -z "$dns_server" ]; then
        log_step "Getting DNS server from Terraform variables..."
        local repo_path
        repo_path=$(get_repo_path) || return 1
        dns_server=$("$repo_path/scripts/get_dns_server.sh")
        
        if [ -n "$dns_server" ] && [ "$dns_server" != "null" ]; then
            log_success "Found DNS server in Terraform: $dns_server"
        else
            dns_server="10.10.10.36"
            log_warning "Could not extract DNS server from Terraform. Using fallback: $dns_server"
        fi
    fi

    # Set default domains if not specified
    if [ -z "$domains" ]; then
        domains="bevz.net,bevz.dev,bevz.pl"
    fi

    log_step "Configuring CoreDNS for local domain resolution..."
    log_info "  DNS Server: $dns_server"
    log_info "  Domains: $domains"
    
    # Convert comma-separated domains to space-separated for Ansible
    local domains_list
    domains_list=$(echo "$domains" | tr ',' ' ')
    
    # Confirmation
    read -r -p "Continue with CoreDNS configuration? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "Operation cancelled."
        return 0
    fi

    # Run the Ansible playbook
    log_step "Running CoreDNS configuration playbook..."
    ansible_run_playbook configure_coredns_local_domains.yml -l control_plane \
        -e "pihole_dns_server=$dns_server" \
        -e "local_domains=[\"$(echo "$domains" | sed 's/,/","/g')\"]"
    
    if [ $? -eq 0 ]; then
        log_success "CoreDNS configured successfully!"
        log_info "Local domains ($domains) will now be forwarded to $dns_server"
    else
        log_error "Error configuring CoreDNS"
        return 1
    fi
}

# Display help information for the upgrade-addons command
cluster_show_upgrade_addons_help() {
    echo "Usage: cpc upgrade-addons [--addon <name>] [--version <version>]"
    echo ""
    echo "Install or upgrade cluster addons. Shows interactive menu if no --addon specified."
    echo ""
    echo "Options:"
    echo "  --addon <name>     Force specific addon to install/upgrade (skips menu)"
    echo "  --version <version> Target version for the addon (default: from environment variables)"
    echo ""
    echo "Available addons:"
    echo "  - calico: Calico CNI networking"
    echo "  - metallb: MetalLB load balancer"
    echo "  - metrics-server: Kubernetes Metrics Server"
    echo "  - coredns: CoreDNS DNS server"
    echo "  - cert-manager: Certificate manager for Kubernetes"
    echo "  - kubelet-serving-cert-approver: Automatic approval of kubelet serving certificates"
    echo "  - argocd: ArgoCD GitOps continuous delivery"
    echo "  - ingress-nginx: NGINX Ingress Controller"
    echo "  - all: Install/upgrade all addons"
    echo ""
    echo "Examples:"
    echo "  cpc upgrade-addons                    # Show interactive menu"
    echo "  cpc upgrade-addons --addon all        # Install all addons directly"
    echo "  cpc upgrade-addons --addon calico     # Install only Calico"
}

# Display help information for the configure-coredns command
cluster_show_configure_coredns_help() {
    echo "Usage: cpc configure-coredns [--dns-server <ip>] [--domains <domain1,domain2,...>]"
    echo ""
    echo "Configure CoreDNS to forward local domain queries to Pi-hole DNS server."
    echo ""
    echo "Options:"
    echo "  --dns-server <ip>    Pi-hole DNS server IP (default: from dns_servers variable in Terraform)"
    echo "  --domains <list>     Comma-separated list of domains (default: bevz.net,bevz.dev,bevz.pl)"
    echo ""
    echo "This command will:"
    echo "  1. Backup current CoreDNS ConfigMap"
    echo "  2. Add local domain forwarding blocks to CoreDNS configuration"
    echo "  3. Restart CoreDNS deployment"
    echo "  4. Verify DNS resolution"
    echo ""
    echo "Examples:"
    echo "  cpc configure-coredns                                    # Use defaults"
    echo "  cpc configure-coredns --dns-server 192.168.1.10         # Custom Pi-hole IP"
    echo "  cpc configure-coredns --domains example.com,test.local  # Custom domains"
}

# Export cluster operations functions
export -f cpc_cluster_ops cluster_upgrade_addons cluster_configure_coredns
export -f cluster_show_upgrade_addons_help cluster_show_configure_coredns_help
